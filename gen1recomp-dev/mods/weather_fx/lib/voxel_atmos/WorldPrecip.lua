-- ============================================================================
-- INDEPENDENT WORLD-SPACE WEATHER PARTICLES
-- ============================================================================
-- Architecture (absolute rules):
--   WORLD → WEATHER STATE / WIND → PARTICLE SIM → individual {x,y,z,vx,vy,vz,life}
--   Wind is world-space and NOT CAMERA-relative; camera rotation/orientation
--   may only change what is visible, never the direction particles physically travel.
--   Camera only *views* particles (billboard). Camera never parents or orients the sim.
--   Player position only *streams* the active volume; particles do not inherit player motion.
--   Each rain/snow/grain particle has its own position, velocity, lifetime, size, seed.
--   Respawn uses world coords around player focus — never "in front of camera".
--   Off-screen particles keep integrating until lifetime/range ends.
-- ============================================================================
--
-- WHY THIS FILE WAS REWRITTEN (4.28.69) — read before "simplifying" anything.
--
-- 1. THIS MODULE DID NOT LOAD AT ALL UNDER LUAJIT.
--    The old `hash()` helper used `~`, `>>` and `&`. Those are Lua 5.3
--    operators. LuaJIT is 5.1 and has no bitwise operators at all — it has the
--    `bit` library instead. So the file was a *compile* error, `V.require
--    ("WorldPrecip")` threw, `WorldPrecip` stayed nil forever, and
--    CinematicAtmos silently took its `else` branch: `drawRain` and, since
--    4.28.68 disabled `drawSnow3D`, no 3D snow of any kind. Every "the snow is
--    a flat overlay" report traces to this one line. `hash()` was never called
--    by anything, so nothing else hinted at it. It is gone; the float-only
--    `fhash()` below replaces it and is Lua 5.1-safe.
--
-- 2. FOUR FUNCTIONS WERE CALLED BUT NEVER DEFINED.
--    `far()`, `addGroundSnow()`, `spawnGrainAt()` were plain nil globals, and
--    `getGrainShader` was called ~16 lines above its `local function`
--    declaration (so it resolved as a nil global too). `WP.update` and
--    `WP.draw` share one `protected-call` in CinematicAtmos, so each of these aborted
--    the whole frame's precipitation with no log line. Even on a Lua 5.4 host
--    where the file compiles, rain died on its first particle. All four are
--    defined now, and every helper is declared before its first use.
--
-- 3. `ensureGSnow()` existed and was never called, so `gsnow.n` stayed 0,
--    `gsnow.active` was never assigned, and ground accumulation could not draw.
--
-- 4. THE DRAW PATH ALLOCATED ~25,000 LUA TABLES PER FRAME.
--    `verts[#verts+1] = { ... }` per vertex, plus a fresh `push` closure per
--    particle. At the snow cap that is 4200 x 6 tables + 4200 closures every
--    frame — the GC, not the GPU, was the ceiling. Vertices now go into a
--    persistent preallocated buffer that is mutated in place and uploaded as a
--    prefix (`setVertices(buf, 1, n)` + `setDrawRange`). Steady-state
--    allocation in the draw path is zero.
--
-- 5. SNOW SPENT ITS BUDGET WHERE IT COULD NOT BE SEEN.
--    720-unit radius against rain's known-good 220. Area goes as r^2, so ~90%
--    of flakes lived past the distance where a sub-unit billboard covers less
--    than a pixel — paying full sim + vertex cost to render nothing, while the
--    space you actually walk through was empty. Snow now uses a 300-unit volume
--    with radial sampling biased hard toward the focus, so the budget lands
--    within arm's reach and out to the fog line. See SNOW_RADIAL_BIAS.
--
-- 6. FLAKES EVAPORATED IN MID-AIR. `maxLife` was a flat 3.5-10.5s while the
--    spawn ceiling was up to 300 units at ~8 units/s of fall. Most flakes
--    expired well above head height and were recycled — which is precisely the
--    "screensaver" read: snow that never arrives anywhere. Lifetime is now
--    *derived* from the fall: time-to-ground plus a margin. Flakes land.
--
-- 7. `snow.rot` / `snow.spin` were simulated every frame and then never used by
--    the renderer. Every flake drew as the same axis-aligned soft blob. The
--    billboard basis is rotated now, so flakes tumble.
--
-- What is deliberately NOT changed: every rain constant, rain's spawn function,
-- rain's integration and rain's streak geometry are the original values and the
-- original math. The rain look is a known-good reference and the brief was
-- explicit. Rain only gains the shared allocation-free buffer, which changes
-- cost, not appearance. The cloud bank lives in CinematicAtmos.drawClouds and
-- is not touched here; snow's spawn ceiling only *reads* a deck height so
-- flakes fall out of the bank instead of out of a fixed slab.
-- ============================================================================

local V = ...
V.safeCall = V.safeCall or pcall

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, random = math.sin, math.cos, math.random
local PI2 = math.pi * 2

local WP = {}
local lastStreamFocus = nil  -- persistent {x,y,z}; mutated, never reallocated per frame

-- 8.1.79: procedural draw/probe option vectors are persistent. The procedural
-- backends consume them synchronously and never retain them, so this removes
-- hot-frame eye/wind/tint table churn without changing any weather counts,
-- distances, wind, tint, collision probes or rendered-world ownership.
WP._procScratch={
  zero3={0,0,0},snowEye={0,0,0},
  rainProbe={eye={0,0,0},wind={0,0},tint={1,1,1}},
  rainDraw={eye={0,0,0},wind={0,0},tint={1,1,1}},
  snowProbe={eye={0,0,0},wind={0,0},tint={1,1,1}},
  snowDraw={eye={0,0,0},wind={0,0},tint={1,1,1}},
  grainProbe={eye={0,0,0},wind={0,0},tint={1,1,1}},
  grainDraw={eye={0,0,0},wind={0,0},tint={1,1,1}},
}
function WP._procVectors(o,ex,ey,ez,wx,wz,r,g,b)
  local e,w,t=o.eye,o.wind,o.tint
  e[1],e[2],e[3]=ex,ey,ez
  w[1],w[2]=wx or 0,wz or 0
  t[1],t[2],t[3]=r or 1,g or 1,b or 1
  return o
end

-- ---------------------------------------------------------------------------
-- TUNABLES
-- ---------------------------------------------------------------------------
-- Rain values are the shipped ones and are not to be retuned here.
-- RAIN, brought to parity with snow in 4.28.72.
--
-- Rain was already genuinely 3D -- world-space streaks with real depth -- and
-- was deliberately left untouched through the snow rework because it was the
-- known-good reference. Measuring it the same way snow was measured showed it
-- shared two of snow's structural problems, just less severely:
--
--   * radial density spread 1.41x inner-to-outer (snow is 1.08x). The 20-layer
--     spawn scheme sampled roughly uniformly in RADIUS, so density fell off as
--     1/r and drops bunched toward the player.
--   * a fixed 900-drop budget over a fixed 220-unit disk, so a wider render
--     distance stretched the same drops thinner instead of raining on more of
--     the world.
--
-- Both now work the way snow does: uniform per-AREA sampling, count derived
-- from rendered tiles, radius following the camera far plane.
local RAIN_MAX = 12000
-- Heavy-weather (HEAVY / PRIML) spawn & fall scale; 1 = normal rain.
local RAIN_HEAVY_SPAWN_MUL = 1.0
local RAIN_HEAVY_FALL_MUL = 1.0
-- Rain at 2.0/tile read as a light drizzle beside snow's 8.0. Rain streaks are
-- also on screen for far less time than a flake (they fall ~8x faster), so the
-- same nominal density looks thinner. 6.0 measured.
local RAIN_PER_TILE = 18.0
local STREAM_RADIUS = 220
local STREAM_R2 = STREAM_RADIUS * STREAM_RADIUS
-- Rain deck, matching snow's single-deck approach.
local RAIN_CEIL = 26 -- original pre-8.1.22 deck; menu scale selects 100%/150%
local RAIN_CEIL_SPAN = 90

-- Tripled from 600. Note the per-family multipliers below already push past
-- this cap (sand 1.8x0.7 = 1.26), so the CAP is what decides the practical
-- on-screen count for sand and hail -- raising the multipliers alone would have
-- changed nothing. Measured practical counts per 1000 square units before ->
-- after: sand 1.7 -> 5.2, dust 1.4 -> 4.2, ash 0.9 -> 2.6, debris 1.5 -> 4.5.
local GRAIN_MAX = 3600
-- Hail runs on the grain pool but needs far more of them. 600 stones spread
-- over the whole streaming volume rendered as a handful of dots drifting past
-- -- nothing like a hailstorm. Hail is also the cheapest grain to draw (no
-- tumble, tight quads), so the extra count is affordable.
-- Hail is small and sparse-looking per stone, so it needs a higher count than
-- the other grain families to read as a hailstorm rather than a drizzle of
-- pellets.
local HAIL_MAX = 45000

-- Snow. Every one of these is reachable from WP.tune() because none of them
-- can be verified without a human looking at the screen.
--
-- ONE TILE IS 16 WORLD UNITS. CinematicAtmos's puddle and snow-pack scans both
-- index map cells as `cx * 16 + 8`, so that is the conversion for anything
-- expressed in tiles below.
local TILE = 16

-- Hard ceiling on live flakes. This is a budget, not a target: the actual count
-- is derived from the rendered area (see SNOW_PER_TILE) and clamped here.
-- Raised with the 3× stream radius so density holds over the larger disc
-- (area scales with r²; without this the field thins and the edge is still
-- walkable).
local SNOW_MAX = 100000

-- FLAKES PER TILE OF RENDERED GROUND, at full intensity.
--
-- This is the number that makes snow cover the world instead of following the
-- player. Deriving the count from area means a wider render distance gets
-- proportionally more flakes rather than stretching the same handful thinner --
-- "if the game is rendering more than normal, it should be snowing everywhere
-- there are rendered tiles". It is also how the rest of CinematicAtmos already
-- works: eachWeatherCell holds density per WORLD CELL constant and lets a
-- landscape viewport cover more cells.
-- 8.0 measured: at the default 300-unit radius that is ~8800 live flakes, just
-- inside SNOW_MAX. Raising it from 3.8 was not cosmetic -- at 3.8 a flake
-- reached the eye roughly once every several minutes, because spreading flakes
-- evenly over the whole rendered disk (correctly) puts far fewer of them within
-- arm's reach than the old near-biased spawn did. Density is the honest dial
-- for that, not a distribution that empties the map.
-- Slight trim vs old 32: 3× radius ≈ 9× area; 22/tile keeps a full sheet
-- under SNOW_MAX without the player walking into empty sky.
local SNOW_PER_TILE = 22.0

-- Radius of the simulated disk. Follows the camera far plane when the host
-- publishes one (same source NightSky and CelestialBodies use), so the snow
-- volume tracks whatever the host is actually rendering.
-- 3× previous defaults so the player cannot out-walk the snow volume.
-- Flakes are already active across the disc (pre-filled), not only at the
-- focus, so the next band is snowing before you reach it.
local SNOW_STREAM_RADIUS = 600
local SNOW_RADIUS_MIN = 320
-- DENSITY, NOT REACH, IS THE CONSTRAINT.
--
-- Particle counts are capped, so widening the disk does not add precipitation
-- -- it spreads the same amount thinner. At a 600-unit far plane a 900 cap
-- gives a 510-unit disk: snow drops to 2.82 flakes/tile and hail to 0.94, both
-- of which read as a thin scatter rather than weather.
--
-- 340 holds the density up while still covering the whole visible field. Past
-- roughly this range a particle is sub-pixel and the fog bed is what reads as
-- distance anyway, so the reach costs nothing and the density is what is seen.
-- Legacy regional precipitation ceiling. 8.1.92 deliberately does NOT use
-- this to clamp the player-local snow field; it remains for regional rain/hail
-- budgeting and the tuning/diagnostic surface.
local SNOW_RADIUS_MAX = 750
local SNOW_FAR_FRACTION = 1.15   -- inherited regional precipitation overlap factor

-- RADIAL SAMPLING EXPONENT.  rad = R * u^BIAS.
--
-- 0.5 is uniform density per unit AREA, which is what real snowfall is and what
-- "snowing all over the rendered world" means. Anything above 0.5 concentrates
-- flakes toward the focus.
--
-- 4.28.69 shipped 4.0 here, chasing near-field density for first person. That
-- was a mistake and it is worth writing down why, because the reasoning looked
-- sound: at 4.0 roughly 38% of live flakes sit within 25 units of you, which
-- reads on screen as a snow globe travelling with the player over an otherwise
-- clear world. Density near the camera is not something the spawn distribution
-- should manufacture -- perspective already delivers it, because near flakes
-- subtend far more screen area than far ones. Distribute uniformly and let the
-- projection do its job; if the near field still looks thin, the fix is more
-- flakes per tile, not a bias that empties the rest of the map.
local SNOW_RADIAL_BIAS = 0.5
local SNOW_MIN_R = 0.6      -- flakes may spawn essentially on top of the focus

-- Culling distance for the vertex build. The sim keeps running past this
-- (architecture rule: off-screen particles keep integrating); we only stop
-- emitting geometry for flakes that cannot cover a pixel.
local SNOW_DRAW_RADIUS = 750

-- Height of the falling column above the focus. ONE deck for the whole field,
-- not a per-flake value that scaled with spawn radius.
--
-- The old version gave near flakes a low ceiling and far flakes a tall one. That
-- silently skewed the standing population: a flake with a short column recycles
-- in a couple of seconds while one with a tall column lives ten times as long,
-- so even a uniform spawn ended up with far more live flakes far away. A single
-- deck height makes standing density match spawn density, which is the only way
-- uniform coverage actually stays uniform.
local SNOW_CEIL = 96 -- original pre-8.1.22 deck; menu scale selects 100%/150%
local SNOW_CEIL_SPAN = 64
local SNOW_LIFE_MARGIN = 1.15   -- x time-to-ground, so flakes land, not vanish
local SNOW_LIFE_CAP = 60

-- Face contact. A flake that passes within FACE_R of the eye is consumed and
-- leaves a melting speck. This is a *consequence of the simulation* — the
-- speck exists only because a real simulated flake really intersected the eye
-- sphere — not a screen-space overlay bolted on top. It is drawn as world
-- geometry in the same depth-tested pass as everything else.
-- A tile is 16 units, so a head is about 6 units across. 1.5 was a guess that
-- made contact vanishingly rare once the field became uniform; 3.0 is the
-- actual scale of the thing being hit. Measured at the default density this is
-- one flake on the face roughly every 10 seconds -- present, not constant.
local FACE_R = 3.0
local FACE_R2 = FACE_R * FACE_R
local FACE_MAX = 20
local FACE_LIFE = 1.35
local FACE_DIST = 0.55      -- how far off the eye the speck sits

-- Ground plane, measured down from the focus.
--
-- Was 1.5, which left flakes settling a tile above where the world's floor
-- reads. GROUND_EXTRA_TILES is the correction and is expressed in tiles rather
-- than raw units so it stays meaningful if the focus origin ever moves; raise
-- it to 2 if snow still stops short, drop it to 0 to restore the old plane.
local GROUND_EXTRA_TILES = 1
local GROUND_DROP = 1.5 + GROUND_EXTRA_TILES * TILE

-- ---------------------------------------------------------------------------
-- POOLS  (struct-of-arrays; index-parallel, never re-sorted)
-- ---------------------------------------------------------------------------
local rain = { n = 0, active=0, simActive=0, gpuActive=0, gpuFullVisual=false, simRadius=0, fieldBottomY=nil, cpuAnchorX=nil, cpuAnchorZ=nil, cpuAnchorCell=nil, clock={wall0=nil,sim0=nil,last=nil,updateWall=nil}, x={},y={},z={}, vx={},vy={},vz={}, hSpeed={}, life={}, maxLife={}, size={}, a={}, id={}, seed={}, grav={} }
local snow = { n = 0, active=0, simActive=0, gpuActive=0, gpuFullVisual=false, simRadius=0, clock={wall0=nil,sim0=nil,last=nil}, x={},y={},z={}, vx={},vy={},vz={}, hSpeed={}, life={}, maxLife={}, size={}, a={}, ph={}, id={}, seed={}, rot={}, spin={}, y0={}, pathH={}, br={} }
-- kind: 1=hail, 2=sand, 3=debris/leaves, 4=ash, 5=black ash
local grain = { n = 0, active=0, x={},y={},z={}, vx={},vy={},vz={}, life={}, maxLife={}, size={}, a={}, kind={}, spin={}, id={}, seed={}, target={0,0,0,0}, simTarget={0,0,0,0}, gpuTarget={0,0,0,0}, gpuFullVisual={false,false,false,false}, start={1,1,1,1}, simRadius={0,0,0,0}, visualRadius={0,0,0,0}, intensity={0,0,0,0}, hSpeed={}, leafSettled={},leafSettleT={},leafSettleLife={},leafNpcT={},leafWallT={} }
local nextId = 1
local function allocId()
  local id = nextId
  nextId = nextId + 1
  if nextId > 1e9 then nextId = 1 end
  return id
end

-- Ground snow patches (accumulate in snow, melt when not snowing).
local GSNOW_MAX = 4800
local gsnow = { n = 0, active=0, x={}, z={}, y={}, baseY={}, height={}, amount={}, size={}, kind={}, class={}, profile={},
  edgeW={}, edgeE={}, edgeN={}, edgeS={}, r1={},r2={},r3={},r4={},r5={},r6={},r7={},r8={} }
local gsnowCursor = 0
local groundSnowTarget = 0  -- 0..1 desired coverage from weather
local FOOT_MAX = 192
local foot = { active=0, x={},y={},z={}, angle={},size={},a={},side={},depression={} }

-- Ground wet marks: appear where a drop lands, dry after WET_LIFE seconds.
-- Splashes are brief. 1.0s made every impact linger as a puddle.
local WET_LIFE = 0.42
local WET_MAX = 1400
-- style: 1=soil/default, 2=vegetation, 3=hard/roof-adjacent, 4=water, 5=ice
local wet = { n = 0, active = 0, x={}, z={}, y={}, age={}, life={}, size={}, a={}, style={} }
local wetCursor = 0

-- Melting specks on the eye, seeded only by real flake/eye intersections.
local face = { n = 0, active = 0, dx={}, dy={}, dz={}, age={}, size={}, seed={} }
local faceCursor = 0
local faceHitTotal = 0

-- Fate counters. A flake that expires in mid air never arrived anywhere, and a
-- field where most flakes do that is the thing that reads as a screensaver.
-- These are on the debug line so the ratio is checkable at a glance, and the
-- test suite asserts on them -- ground-snow coverage cannot stand in for this,
-- because ambient scatter seeds drifts whether or not a single flake lands.
-- Drops that finished on the ground. Counted separately from the wet-mark pool
-- because that pool is ALSO fed by ambient scatter across the rain volume, so
-- "are there splashes alive" is true whether or not a single drop ever lands.
-- A test asserting on pool occupancy passed cleanly with ground impacts deleted
-- entirely -- exactly the way ground-snow coverage failed to witness flakes
-- landing.
local rainLanded = 0
local snowLanded = 0
local snowExpiredAir = 0

-- Deepest a flake has actually descended below the focus, in world units.
-- Exists because GROUND_DROP is a constant, and a constant is exactly the kind
-- of thing a test can assert on without proving the simulation honours it --
-- removing a whole tile of fall depth changed no test result at all until this
-- was added. What matters is where flakes REACH, not what the constant says.
local snowDeepest = 0

local rainMesh, snowMesh, wetMesh, grainMesh, gsnowMesh, footMesh, faceMesh
local rainShader, cardFallbackShader, snowShader, snowShaderBall, grainShader
-- 8.0.1 MAX fast path. The simulation still owns every snowflake, but capable
-- GPUs receive one compact instance row per visible flake instead of six Lua
-- vertex rows. The legacy CPU billboard path below remains the fail-open path.
local snowInstance = {base=nil,instances=nil,cap=0,rows={},rowCap=0,shader=nil,shaderBall=nil,failed=false,prefix=true,chunk=8192}
local simTime = 0
WP._animationPaused=false
-- 8.1.77 rain phase clock: procedural rain must not inherit short gameplay
-- update stalls while the player presses against a map edge or rotates in place.
-- Use a monotonic wall clock when the host exposes one, with simTime fallback for
-- deterministic/headless hosts. CPU rain gets the same bounded wall-delta catch-up.
function WP._rainVisualTime()
  local c=rain.clock
  local wall=nil
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=V.safeCall(love.timer.getTime)
    if ok and tonumber(v) then wall=tonumber(v) end
  end
  if wall then
    if c.wall0==nil then c.wall0=wall;c.sim0=simTime end
    if WP._animationPaused then
      if c.pauseWall==nil then c.pauseWall=wall end
      if c.last==nil then c.last=simTime end
      return c.last
    end
    if c.pauseWall~=nil then
      c.wall0=(tonumber(c.wall0) or wall)+(wall-c.pauseWall)
      c.pauseWall=nil
    end
    local t=(tonumber(c.sim0) or simTime)+(wall-(tonumber(c.wall0) or wall))
    if c.last and t<c.last then t=c.last end
    c.last=t
    return t
  end
  c.last=simTime
  return simTime
end
-- 8.1.83 snow presentation clock: the procedural snow field must advance from
-- monotonic presentation time just like rain. Raw simulation dt can arrive in
-- uneven chunks on low-power hosts, which makes an otherwise continuous shader
-- visibly step. This changes no fall-speed coefficient or wind equation.
function WP._snowVisualTime()
  local c=snow.clock
  local wall=nil
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=V.safeCall(love.timer.getTime)
    if ok and tonumber(v) then wall=tonumber(v) end
  end
  if wall then
    if c.wall0==nil then c.wall0=wall;c.sim0=simTime end
    if WP._animationPaused then
      if c.pauseWall==nil then c.pauseWall=wall end
      if c.last==nil then c.last=simTime end
      return c.last
    end
    if c.pauseWall~=nil then
      c.wall0=(tonumber(c.wall0) or wall)+(wall-c.pauseWall)
      c.pauseWall=nil
    end
    local t=(tonumber(c.sim0) or simTime)+(wall-(tonumber(c.wall0) or wall))
    if c.last and t<c.last then t=c.last end
    c.last=t
    return t
  end
  c.last=simTime
  return simTime
end

function WP._rainFrameDt(inputDt)
  local c=rain.clock
  local d=tonumber(inputDt) or 0
  if d<0 then d=0 end
  if WP._animationPaused then
    if love and love.timer and type(love.timer.getTime)=="function" then
      local ok,v=V.safeCall(love.timer.getTime)
      if ok and tonumber(v) then c.updateWall=tonumber(v) end
    end
    return 0
  end
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=V.safeCall(love.timer.getTime)
    if ok and tonumber(v) then
      local now=tonumber(v)
      if c.updateWall~=nil then
        local wd=now-c.updateWall
        if wd>=0 and wd<2.0 then d=math.max(d,wd) end
      end
      c.updateWall=now
    end
  end
  if d>0.25 then d=0.25 end
  return d
end
local lastEye = nil          -- filled by draw(); update() uses it for face hits
local lastLookY = nil        -- sine of the look pitch, from eye -> focus

-- CAMERA MODE. The host does not publish its voxel tilt, but it publishes eye
-- and focus, and the look pitch between them separates the settings cleanly:
--
--     tilt 15  -75 deg     tilt 75    -21 deg
--     tilt 35  -60 deg     3rd person -22 deg
--     tilt 50  -45 deg     1st person   0 deg
--
-- -32 degrees splits {15, 35, 50} from {75, 3rd, 1st}, which is the division
-- the weather should follow: the steep map-like tilts are looking DOWN at the
-- world and want the flat overhead treatment, while 75 / 3rd / 1st are looking
-- THROUGH it and want the immersive first-person one.
local IMMERSIVE_SIN = -0.5299   -- sin(-32 degrees)
local lastFar = nil          -- filled by draw(); the host's camera far plane
local drawnSnowVerts = 0
local drawnRainVerts = 0
-- A family can be healthy with zero visible vertices when the 4.33.1+ rear-camera
-- culling proves every simulated particle is outside the view. Ownership must
-- follow draw-path health, not vertex count, or the flat 2D fallback appears on
-- top of an otherwise healthy 3D storm whenever a family is fully culled.
local drawnSnowHealthy = false
local drawnRainHealthy = false
-- Per-family geometry/health on the last 3D draw.
-- kind: 1=hail, 2=sand, 3=debris/leaves, 4=ash.
local drawnGrainVerts = { [1]=0, [2]=0, [3]=0, [4]=0 }
local drawnGrainHealthy = { [1]=false, [2]=false, [3]=false, [4]=false }

-- ---------------------------------------------------------------------------
-- MATH HELPERS
-- ---------------------------------------------------------------------------

-- Float-only hash. Replaces the 5.3-bitwise version that would not compile
-- under LuaJIT. Deterministic per (i, salt), 0..1, no integer ops.
local function fhash(i, salt)
  local n = (i * 0.6180339887 + salt * 0.7548776662) * 43758.5453
  return n - floor(n)
end

-- Sine lookup. Snow turbulence is 3 trig calls per flake per frame; at the cap
-- that is ~12,600 libm calls a frame for a wobble nobody can measure to the
-- fourth decimal. A 1024-entry table is visually identical and much cheaper.
local SIN_N = 1024
local SIN_TAB = {}
for i = 0, SIN_N - 1 do SIN_TAB[i] = sin(i * PI2 / SIN_N) end
local SIN_SCALE = SIN_N / PI2
local COS_OFF = floor(SIN_N * 0.25)
local function fsin(a)
  return SIN_TAB[floor(a * SIN_SCALE) % SIN_N]
end
local function fcos(a)
  return SIN_TAB[(floor(a * SIN_SCALE) + COS_OFF) % SIN_N]
end

-- Was called on every rain and grain particle every frame and never existed.
-- Squared compare; no sqrt.
local function far(x, z, px, pz)
  local dx, dz = x - px, z - pz
  return (dx * dx + dz * dz) > STREAM_R2
end

local function steerHorizontalCached(vx, vz, dirX, dirZ, speed, amount)
  amount = math.max(0, math.min(1, tonumber(amount) or 0))
  speed = tonumber(speed) or 0
  if amount <= 0 or speed < 1e-5 then return vx, vz end
  local tx, tz = dirX * speed, dirZ * speed
  return vx + (tx-vx)*amount, vz + (tz-vz)*amount
end
local function steerHorizontal(vx, vz, dirX, dirZ, amount)
  return steerHorizontalCached(vx,vz,dirX,dirZ,math.sqrt(vx*vx+vz*vz),amount)
end


-- ---------------------------------------------------------------------------
-- POOL GROWTH
-- ---------------------------------------------------------------------------
local function ensureRain(n)
  while rain.n < n do
    local i = rain.n + 1
    rain.x[i], rain.y[i], rain.z[i] = 0, 0, 0
    rain.vx[i], rain.vy[i], rain.vz[i], rain.hSpeed[i] = 0, -1, 0, 0
    rain.life[i], rain.maxLife[i] = 0, 1
    rain.size[i], rain.a[i] = 1, 1
    rain.id[i], rain.seed[i], rain.grav[i] = 0, 0, 18
    rain.n = i
  end
end

local function ensureSnow(n)
  while snow.n < n do
    local i = snow.n + 1
    snow.x[i], snow.y[i], snow.z[i] = 0, 0, 0
    snow.vx[i], snow.vy[i], snow.vz[i], snow.hSpeed[i] = 0, -1, 0, 0
    snow.life[i], snow.maxLife[i] = 0, 1
    snow.size[i], snow.a[i], snow.ph[i] = 1, 1, 0
    snow.id[i], snow.seed[i] = 0, 0
    snow.rot[i], snow.spin[i] = 0, 0
    snow.y0[i], snow.pathH[i] = 0, 100
    snow.br[i] = 1
    snow.n = i
  end
end

local function ensureGrain(n)
  while grain.n < n do
    local i = grain.n + 1
    grain.x[i], grain.y[i], grain.z[i] = 0, 0, 0
    grain.vx[i], grain.vy[i], grain.vz[i] = 0, -1, 0
    grain.life[i], grain.maxLife[i] = 0, 1
    grain.size[i], grain.a[i] = 1, 1
    grain.kind[i], grain.spin[i] = 2, 0
    grain.id[i], grain.seed[i] = 0, 0
    grain.hSpeed[i] = 0
    grain.leafSettled[i], grain.leafSettleT[i], grain.leafSettleLife[i] = false, 0, 0
    grain.leafNpcT[i], grain.leafWallT[i] = 0, 0
    grain.n = i
  end
end


-- 8.1.54 residency trim. Kept on WP rather than as another main-chunk local:
-- this module is already at Lua 5.1/LuaJIT's hard 200-local chunk limit.
function WP._trimPool(pool,n,kind)
  n=max(0,floor(tonumber(n) or 0))
  if (pool.n or 0)<=n then return end
  local fields
  if kind=="rain" then
    fields={'x','y','z','vx','vy','vz','hSpeed','life','maxLife','size','a','id','seed','grav'}
  elseif kind=="snow" then
    fields={'x','y','z','vx','vy','vz','hSpeed','life','maxLife','size','a','ph','id','seed','rot','spin','y0','pathH','br'}
  else
    fields={'x','y','z','vx','vy','vz','life','maxLife','size','a','kind','spin','id','seed','hSpeed','leafSettled','leafSettleT','leafSettleLife','leafNpcT','leafWallT'}
  end
  for fi=1,#fields do
    local k=fields[fi];local old=pool[k];local fresh={}
    for i=1,n do fresh[i]=old[i] end
    pool[k]=fresh
  end
  pool.n=n
end

local function ensureGSnow()
  while gsnow.n < GSNOW_MAX do
    local i = gsnow.n + 1
    gsnow.x[i], gsnow.z[i], gsnow.y[i], gsnow.baseY[i], gsnow.height[i] = 0, 0, 0, 0, 0
    gsnow.amount[i], gsnow.size[i], gsnow.kind[i], gsnow.class[i], gsnow.profile[i] = 0, 1, "ground", "ground", "full"
    gsnow.edgeW[i], gsnow.edgeE[i], gsnow.edgeN[i], gsnow.edgeS[i] = 0, 0, 0, 0
    gsnow.r1[i],gsnow.r2[i],gsnow.r3[i],gsnow.r4[i]=1,1,1,1
    gsnow.r5[i],gsnow.r6[i],gsnow.r7[i],gsnow.r8[i]=1,1,1,1
    gsnow.n = i
  end
end

local function ensureWet()
  while wet.n < WET_MAX do
    local i = wet.n + 1
    wet.x[i], wet.z[i], wet.y[i] = 0, 0, 0
    wet.age[i], wet.life[i], wet.size[i], wet.a[i], wet.style[i] = 99, WET_LIFE, 1, 0, 1
    wet.n = i
  end
end

local function ensureFace()
  while face.n < FACE_MAX do
    local i = face.n + 1
    face.dx[i], face.dy[i], face.dz[i] = 0, 1, 0
    face.age[i], face.size[i], face.seed[i] = 99, 1, 0
    face.n = i
  end
end

local settingsModule, qualityModule, sceneModule, windModule, leafPhysicsModule, snowPackModule, hostVoxelSceneModule, hostTileShapeModule
local environmentSurfaceModule, particleBatcherModule

local function environmentSurface()
  if environmentSurfaceModule~=nil then return environmentSurfaceModule or nil end
  local ok,m=V.safeCall(V.require,"EnvironmentSurface")
  environmentSurfaceModule=(ok and m) or false
  return environmentSurfaceModule or nil
end

local function particleBatcher()
  if particleBatcherModule~=nil then return particleBatcherModule or nil end
  local ok,m=V.safeCall(V.require,"ParticleBatcher")
  particleBatcherModule=(ok and m) or false
  return particleBatcherModule or nil
end

-- ---------------------------------------------------------------------------
-- DEPOSITS  (ring buffers — bounded, no allocation, no compaction)
-- ---------------------------------------------------------------------------
WP._worldInteractionPrecip=nil
function WP._interactionPrecip()
  if WP._worldInteractionPrecip~=nil then return WP._worldInteractionPrecip or nil end
  local ok,m=V.safeCall(V.require,"WorldInteractionPrecip")
  WP._worldInteractionPrecip=(ok and m) or false
  return WP._worldInteractionPrecip or nil
end
local function addWetMark(x, y, z, size, kind, class, art)
  local PI=WP._interactionPrecip()
  local material,style,sizeMul,life,alphaMul="soil",1,.70,.30,.78
  if PI and PI.impactProfile then material,style,sizeMul,life,alphaMul=PI.impactProfile(kind,class,art) end
  local ES=environmentSurface()
  if material~="water" and ES and ES.depositWet then
    local ok,accepted=V.safeCall(ES.depositWet,x,z,0.035+(size or .4)*.018,material)
    if ok and accepted==false then return false end
  end
  ensureWet();wetCursor=wetCursor%WET_MAX+1;local i=wetCursor
  wet.x[i],wet.z[i],wet.y[i]=x,z,y;wet.age[i]=0;wet.life[i]=life or WET_LIFE;wet.style[i]=style or 1
  wet.size[i]=max(.16,(size or .4)*sizeMul*(.55+random()*.5));wet.a[i]=(.30+random()*.35)*alphaMul
  if wetCursor>wet.active then wet.active=wetCursor end;return true
end

-- SPLASHES menu row (same as 2D). Cached 1s.
local splashOn, splashAt = true, -1
local function splashesEnabled()
  if simTime - splashAt < 1.0 then return splashOn end
  splashAt = simTime
  splashOn = true
  local S = settingsModule()
  if S and S.is and S.is("splash", "off") then splashOn = false end
  return splashOn
end

-- Was a nil global. Called wherever a flake reaches the ground plane.
local function addGroundSnow(x, y, z, size)
  -- Visible 3D snow splash/spot discs remain disabled by player request, but
  -- the sparse environment engine still records snow depth for temperature,
  -- melting, future footprints and other systems without allocating a draw object.
  local ES=environmentSurface()
  if ES and ES.depositSnow then V.safeCall(ES.depositSnow,x,z,0.020+(size or .4)*.010) end
  return
end

local function addFaceHit(dx, dy, dz, size)
  ensureFace()
  local l = sqrt(dx * dx + dy * dy + dz * dz)
  if l < 1e-4 then return end
  faceCursor = faceCursor % FACE_MAX + 1
  local i = faceCursor
  face.dx[i], face.dy[i], face.dz[i] = dx / l, dy / l, dz / l
  face.age[i] = 0
  -- A speck sits FACE_DIST (0.55) units from the eye, so its apparent size is
  -- enormous for its world size -- at 0.16x a rain drop it rendered as a white
  -- blob covering a fifth of the frame. Caught by rasterizing a real
  -- VERDANT_RAIN frame and looking at it; no simulation test can see this,
  -- because the speck is exactly where the sim intends.
  --
  -- Sized so a droplet subtends a few degrees, not fifty, and hard-capped so a
  -- large drop cannot produce a large smear.
  face.size[i] = max(0.006, min(0.030, (size or 0.5) * 0.014))
  face.seed[i] = random()
  faceHitTotal = faceHitTotal + 1
  if faceCursor > face.active then face.active = faceCursor end
end

-- ---------------------------------------------------------------------------
-- SPAWNERS
-- ---------------------------------------------------------------------------

-- Absolute lower emission band of the live 3D cloud deck. Set once per update
-- by CinematicAtmos from the same deckY0/deckYSpan used to draw the clouds.
-- nil means the host/profile did not publish a deck, so legacy heights remain a
-- safe fallback instead of making precipitation disappear.
local precipDeckY = nil
local precipDeckSpan = nil
local lastStreamKind = nil

-- 8.1.77 CPU fallback anchoring. Hosts that fail procedural-instancing
-- validation still need true world-space rain. Camera turns must never move/cull
-- the field, and ordinary walking must not recycle every drop around the avatar.
function WP._rainCpuAnchor(px,pz,radius,mapChanged)
  local r=math.max(4,tonumber(radius) or STREAM_RADIUS)
  local cell=math.max(8,math.min(64,r*0.08))
  local tx=math.floor((tonumber(px) or 0)/cell+0.5)*cell
  local tz=math.floor((tonumber(pz) or 0)/cell+0.5)*cell
  if mapChanged or rain.cpuAnchorX==nil then
    rain.cpuAnchorX,rain.cpuAnchorZ,rain.cpuAnchorCell=tx,tz,cell
  else
    local changedCell=math.abs((rain.cpuAnchorCell or cell)-cell)>0.001
    local dx=(tonumber(px) or 0)-(rain.cpuAnchorX or tx)
    local dz=(tonumber(pz) or 0)-(rain.cpuAnchorZ or tz)
    if changedCell or math.abs(dx)>cell*0.72 or math.abs(dz)>cell*0.72 then
      rain.cpuAnchorX,rain.cpuAnchorZ,rain.cpuAnchorCell=tx,tz,cell
    end
  end
  return rain.cpuAnchorX or tx,rain.cpuAnchorZ or tz,cell
end

-- RAIN — authored density/size/fall tuning is unchanged. 8.1.5 changes only
-- the one-shot activation age distribution so a newly selected storm already
-- occupies its physical cloud-to-ground column. Normal recycle still originates
-- in this exact cloud deck.
-- Spawn one particle in the volume around player (full 360 degrees, not view cone).
local function spawnRainAt(i, px, py, pz, intensity, windX, windZ, radiusOverride, primeColumn)
  -- Uniform per-AREA placement over a full 360-degree disk, exactly as snow
  -- does it. sqrt() of a uniform sample is what makes density constant per unit
  -- area; the old 20-layer scheme spread uniformly in radius, which concentrates
  -- as 1/r and bunched rain around the player.
  local seed = random()
  local spawnRadius=max(0.6,tonumber(radiusOverride) or STREAM_RADIUS)
  if WP._uniformPrecipField==true then
    -- CPU fallback mirrors the fronts-OFF rendered-world contract: fill the
    -- complete 2R x 2R voxel window instead of a circle. The anchor is snapped
    -- in absolute world space, so the field does not translate with every step.
    rain.x[i] = px + (random()*2-1) * spawnRadius
    rain.z[i] = pz + (random()*2-1) * spawnRadius
  else
    local ang = random() * PI2
    local u = random()
    local rad = 0.6 + sqrt(u) * (spawnRadius - 0.6)
    rain.x[i] = px + cos(ang) * rad
    rain.z[i] = pz + sin(ang) * rad
  end

  -- ONE deck height for the whole field, not a per-drop ceiling that scaled
  -- with spawn radius. A short column recycles in a fraction of the time a tall
  -- one does, so a radius-dependent ceiling silently skews the standing
  -- population outward even when the spawn itself is uniform -- the same trap
  -- that had to be fixed for snow.
  local rainBase = precipDeckY or (py + RAIN_CEIL*WP._cloudHeightScale())
  local rainSpan = precipDeckSpan or RAIN_CEIL_SPAN
  rain.y[i] = rainBase + random() * rainSpan

  local fall = (48 + random() * 42) * (0.80 + intensity * 0.28) * (RAIN_HEAVY_FALL_MUL or 1)
  local wv = 0.65 + random() * 0.7
  rain.vx[i] = windX * (10 + random() * 14) * wv + (random() - 0.5) * 3.5
  rain.vy[i] = -fall
  rain.vz[i] = windZ * (10 + random() * 14) * wv + (random() - 0.5) * 3.5
  rain.hSpeed[i] = sqrt(rain.vx[i]*rain.vx[i] + rain.vz[i]*rain.vz[i])

  -- Lifetime derived from the fall, so a drop survives long enough to reach the
  -- ground and leave a wet mark instead of expiring in mid air.
  local drop = rain.y[i] - (py - GROUND_DROP)
  rain.maxLife[i] = min(20, (drop / max(1.5, fall)) * 1.15 + 0.3)
  rain.life[i] = 0
  rain.seed[i] = seed
  rain.grav[i] = 18 + seed * 8

  -- First activation represents a storm that is already raining throughout its
  -- physical cloud-to-ground column, not a synchronized sheet in which every
  -- drop was born at the exact same instant. Stratify the initial near-field
  -- pool over fall age so a forward-facing camera sees rain immediately while
  -- still retaining drops beside the live cloud-bank origin. This happens only
  -- on the 0 -> rain transition; every ordinary recycle below calls with false
  -- and therefore visibly starts again at the real cloud deck.
  if primeColumn and drop > 1 then
    local bands = max(2, min(16, tonumber(rain.simActive) or 16))
    local layer = ((i - 1) % bands) / (bands - 1)
    local frac = min(0.86, layer * 0.82 + random() * 0.025)
    local age = (drop / max(1.5, fall)) * frac
    rain.y[i] = rain.y[i] - drop * frac
    rain.x[i] = rain.x[i] + rain.vx[i] * age
    rain.z[i] = rain.z[i] + rain.vz[i] * age
    rain.vy[i] = rain.vy[i] - rain.grav[i] * age
    rain.life[i] = min(max(0, rain.maxLife[i] - 0.05), age)
  end

  rain.size[i] = 0.55 + random() * 1.5
  rain.a[i] = 0.30 + random() * 0.34
  rain.id[i] = allocId()
end

-- SNOW — a world field, not a system that follows you.
--
-- Placement is world XZ around the streaming focus over a full 360-degree disk,
-- Y from the cloud deck down. The camera contributes nothing to placement or
-- orientation; it is a streaming anchor and, at draw time only, a billboard
-- target. Walking moves *you* through a field that was already there.
--
-- THE DISTRIBUTION IS UNIFORM PER UNIT AREA. rad = R * sqrt(u) gives constant
-- flakes-per-tile everywhere inside the disk, which is what makes it snow over
-- the whole rendered world rather than in a dense knot around the player. See
-- SNOW_RADIAL_BIAS for why the previous near-biased version was wrong.
--
-- Two supporting properties, both of which have to hold or uniform spawning
-- still produces a non-uniform field:
--
--   * ONE DECK HEIGHT for every flake. Column height sets lifetime, lifetime
--     sets how long a flake stays counted, so a per-radius column silently
--     reweights the standing population even when spawning is even.
--   * SIZE IS INDEPENDENT OF SPAWN RADIUS. A flake's physical size has nothing
--     to do with where it happened to appear. The old code multiplied size and
--     alpha by a `near` term at spawn AND applied a depth cue again at draw
--     time, attenuating distant flakes twice and helping hollow out the far
--     field. Perspective alone is the correct and sufficient depth cue.
local function spawnSnowAt(i, px, py, pz, intensity, windX, windZ, primeColumn, radiusOverride)
  local seed = random()
  local ang = random() * PI2
  -- Uniform-by-area radial sampling (see SNOW_RADIAL_BIAS).
  local t = random() ^ SNOW_RADIAL_BIAS
  local spawnRadius=max(SNOW_MIN_R,tonumber(radiusOverride) or SNOW_STREAM_RADIUS)
  local rad = SNOW_MIN_R + t * (spawnRadius - SNOW_MIN_R)
  snow.x[i] = px + cos(ang) * rad
  snow.z[i] = pz + sin(ang) * rad

  -- Fall FROM THE ACTUAL 3D CLOUD BANK when CinematicAtmos publishes it.
  -- This is an absolute world Y shared with the cloud descriptors, not a camera
  -- or player-relative ceiling. Legacy hosts without deck metadata keep the old
  -- safe sky column instead of losing snow.
  local snowBase = precipDeckY or (py + SNOW_CEIL*WP._cloudHeightScale())
  local snowSpan = precipDeckSpan or SNOW_CEIL_SPAN
  snow.y[i] = snowBase + random() * snowSpan

  -- Soft snowfall. Real flakes settle around 1 m/s; rain here runs 48-90
  -- units/s for roughly 9 m/s, so a unit is about 6 cm and snow wants ~5-12.
  -- Intensity leans it faster (a blizzard drives flakes down, not just sideways).
  -- 40% slower than prior; real flakes settle gently, not like light rain.
  local fall = (5.0 + random() * 6.5) * (0.75 + min(2.2, intensity) * 0.30) * 0.60
  local wv = 0.55 + random() * 1.35
  -- Base drift is never pure vertical: each flake gets a personal wind lean.
  snow.vx[i] = windX * (5 + random() * 16) * wv + (random() - 0.5) * 3.5
  snow.vy[i] = -fall
  snow.vz[i] = windZ * (5 + random() * 16) * wv + (random() - 0.5) * 3.5
  snow.hSpeed[i] = sqrt(snow.vx[i]*snow.vx[i] + snow.vz[i]*snow.vz[i])

  -- Live long enough to land, plus margin for the wobble and for the wind
  -- carrying it out of range first. The old flat 3.5-10.5s expired most flakes
  -- in mid air, which is the single most "fake" thing a snow system can do.
  local drop = snow.y[i] - (py - GROUND_DROP)
  snow.maxLife[i] = min(SNOW_LIFE_CAP, (drop / max(1.5, fall)) * SNOW_LIFE_MARGIN + 0.5)
  snow.life[i] = 0

  snow.size[i] = 0.17 + random() * 0.31
  snow.a[i] = 0.40 + random() * 0.38
  snow.br[i] = 0.82 + random() * 0.18      -- per-flake brightness; breaks up the sheet
  snow.ph[i] = random() * PI2
  snow.rot[i] = random() * PI2
  snow.spin[i] = (random() - 0.5) * 2.4
  snow.seed[i] = seed
  -- Seed-derived coefficients are invariant for this flake lifetime.
  snow.id[i] = allocId()
  snow.y0[i] = snow.y[i]
  snow.pathH[i] = drop

  -- Warm-start a newly activated snow field through the whole physical fall
  -- column. Without this, switching to snow creates every flake at the cloud
  -- ceiling simultaneously; at the deliberately gentle snow fall speed the
  -- lower world can look completely empty for tens of seconds. The flake still
  -- has a cloud-deck origin; we simply initialize it partway along that already-
  -- elapsed trajectory so a selected snow weather looks like an ongoing storm.
  if primeColumn then
    local frac = random() * 0.88
    local fallSpeed = max(1.5, -snow.vy[i])
    local age = (drop / fallSpeed) * frac
    snow.life[i] = min((snow.maxLife[i] or age) * 0.88, age)
    snow.y[i] = snow.y0[i] - drop * frac
    snow.x[i] = snow.x[i] + snow.vx[i] * age * 0.55
    snow.z[i] = snow.z[i] + snow.vz[i] * age * 0.55
  end
end

-- GRAIN — was a nil global; the sand/ash/debris path could never run.
-- kind: 1=hail, 2=sand, 3=debris/leaves, 4=ash, 5=black ash
local function spawnGrainAt(i, px, py, pz, kind, windX, windZ, primeColumn, radiusOverride)
  local seed = random()
  local ang = random() * PI2
  -- UNIFORM PER AREA. This was random()^1.6, and an exponent above 1 pulls
  -- mass toward the centre -- so every grain family (hail, sand, ash, debris)
  -- bunched into a lump directly over the player instead of covering the
  -- rendered map. Reported for hail; sand, ash and debris had it too.
  --
  -- sqrt of a uniform sample is what makes density constant per unit AREA. The
  -- same mistake, with the same fix, as snow (4.29.2) and lightning (4.30.0) --
  -- it simply had not been applied to grains.
  local t = sqrt(random())
  local spawnRadius=max(4,tonumber(radiusOverride) or STREAM_RADIUS)
  local rad = 4 + t * (spawnRadius - 4)
  local near = 1.0 - t
  grain.x[i] = px + cos(ang) * rad
  grain.z[i] = pz + sin(ang) * rad
  grain.kind[i] = kind
  grain.seed[i] = seed
  grain.life[i] = 0
  grain.id[i] = allocId()
  grain.spin[i] = random()
  -- Collision/pile state never survives a recycle or family reassignment.
  grain.leafSettled[i], grain.leafSettleT[i], grain.leafSettleLife[i] = false, 0, 0
  grain.leafNpcT[i], grain.leafWallT[i] = 0, 0

  if kind == 2 then
    -- Real desert sandstorm (kind 2): wall of grit that fills the air.
    -- Four layers so near ground, mid, high, and far haze all obscure vision.
    local layer = random()
    local seed = grain.seed[i] or random()
    -- Stronger base wind so the storm drives hard past the player
    local windBoost = 1.35
    if layer < 0.30 then
      -- Ground blizzard / saltation — dense, opaque, blinds near view
      grain.y[i] = py - 0.8 + random() * 9.0
      local drive = (40 + random() * 50) * windBoost
      grain.vx[i] = windX * drive + (random() - 0.5) * 18
      grain.vy[i] = (random() - 0.30) * 7.5
      grain.vz[i] = windZ * drive + (random() - 0.5) * 18
      grain.maxLife[i] = 1.0 + random() * 1.6
      -- Base size *0.22 (was 0.125): readable from overhead without draw-time
      -- size bombs that turned FPV grit into giant yellow discs.
      grain.size[i] = (0.38 + seed * 0.55) * (0.55 + near * 0.70) * 0.22
      grain.a[i] = 0.48 + random() * 0.32 + near * 0.22
    elseif layer < 0.58 then
      -- Mid storm body — main obscuring wall
      grain.y[i] = py + 3 + random() * 22
      local drive = (32 + random() * 44) * windBoost
      grain.vx[i] = windX * drive + (random() - 0.5) * 16
      grain.vy[i] = -(0.3 + random() * 2.8) + (random() - 0.5) * 2.4
      grain.vz[i] = windZ * drive + (random() - 0.5) * 16
      grain.maxLife[i] = 1.6 + random() * 2.4
      grain.size[i] = (0.22 + seed * 0.42) * (0.50 + near * 0.75) * 0.22
      grain.a[i] = 0.40 + random() * 0.28 + near * 0.24
    elseif layer < 0.82 then
      -- High suspension — washes out the sky / horizon
      grain.y[i] = py + 14 + random() * 38
      local drive = (22 + random() * 34) * windBoost
      grain.vx[i] = windX * drive + (random() - 0.5) * 20
      grain.vy[i] = -(0.1 + random() * 1.4) + (random() - 0.5) * 1.6
      grain.vz[i] = windZ * drive + (random() - 0.5) * 20
      grain.maxLife[i] = 2.6 + random() * 3.8
      grain.size[i] = (0.12 + seed * 0.28) * (0.45 + near * 0.80) * 0.22
      grain.a[i] = 0.28 + random() * 0.22 + near * 0.20
    else
      -- Far haze grit — distant curtain, longer life, fills depth
      grain.y[i] = py + 6 + random() * 30
      local drive = (16 + random() * 26) * windBoost
      grain.vx[i] = windX * drive + (random() - 0.5) * 22
      grain.vy[i] = -(0.05 + random() * 1.0) + (random() - 0.5) * 1.2
      grain.vz[i] = windZ * drive + (random() - 0.5) * 22
      grain.maxLife[i] = 3.4 + random() * 4.2
      grain.size[i] = (0.10 + seed * 0.22) * (0.40 + near * 0.85) * 0.22
      grain.a[i] = 0.22 + random() * 0.18 + near * 0.14
    end
  elseif kind == 4 then
    -- Ashfall from the cinematic cloud bank (same deck height as 3D snow).
    -- Half grey ash, half black ash (spin >= 0.5 → black in drawGrainPass).
    local ashBase = precipDeckY or (py + SNOW_CEIL*WP._cloudHeightScale())
    local ashSpan = precipDeckSpan or SNOW_CEIL_SPAN
    grain.y[i] = ashBase + random() * ashSpan
    -- Drift while falling so flakes read as ash, not rain
    grain.vx[i] = windX * (4 + random() * 9) + (random() - 0.5) * 5
    -- Fall speed: reach ground from cloud deck within lifetime
    grain.vy[i] = -(5.5 + random() * 7.5)
    grain.vz[i] = windZ * (4 + random() * 9) + (random() - 0.5) * 5
    local dist = max(1.0, grain.y[i] - (py - GROUND_DROP))
    local speed = max(1.0, -grain.vy[i])
    grain.maxLife[i] = (dist / speed) * 1.25 + random() * 4.0
    grain.size[i] = (0.28 + random() * 0.50) * (0.55 + near * 0.75)
    grain.a[i] = 0.28 + random() * 0.32 + near * 0.22
    -- Explicit 50/50 grey vs black ash
    grain.spin[i] = (random() < 0.5) and (0.15 + random() * 0.30) or (0.55 + random() * 0.40)
  elseif kind == 3 then
    -- Real wind-blown leaves: flutter, tumble, drift past at mixed heights.
    local seed = grain.seed[i] or random()
    local layer = random()
    -- Size mix: small flakes to full leaves.
    --
    -- Halved from 0.45 + seed*1.15 (range 0.45-1.60) at request -- leaves were
    -- reading too large in the world. Scaled at the SOURCE rather than in the
    -- draw path so the quad's aspect ratio is untouched: the shader carves the
    -- ovate silhouette from the quad's UV, so changing width and length
    -- separately would distort the leaf shape rather than just shrink it.
    -- Halved again at request: leaves were still reading as large fans. Total
    -- reduction from the original 0.45-1.60 range is 4x, to 0.1125-0.40.
    local leafScale = (0.45 + seed * 1.15) * 0.25
    if layer < 0.35 then
      -- Low skip — leaves skimming near the ground
      grain.y[i] = py + random() * 10
      local drive = 18 + random() * 28
      grain.vx[i] = windX * drive + (random() - 0.5) * 14
      grain.vy[i] = (random() - 0.25) * 5.0
      grain.vz[i] = windZ * drive + (random() - 0.5) * 14
      grain.maxLife[i] = (2.0 + random() * 2.8) * 5.0
    elseif layer < 0.70 then
      -- Main drift — classic leaves blowing past at eye level
      grain.y[i] = py + 6 + random() * 22
      local drive = 14 + random() * 32
      grain.vx[i] = windX * drive + (random() - 0.5) * 18
      -- Flutter lift: some rise, some sink
      grain.vy[i] = -(0.2 + random() * 2.5) + random() * 4.5
      grain.vz[i] = windZ * drive + (random() - 0.5) * 18
      grain.maxLife[i] = (2.8 + random() * 3.6) * 5.0
    else
      -- High loft — leaves spinning high in the wind
      grain.y[i] = py + 16 + random() * 36
      local drive = 10 + random() * 26
      grain.vx[i] = windX * drive + (random() - 0.5) * 20
      grain.vy[i] = -(0.1 + random() * 1.8) + random() * 3.5
      grain.vz[i] = windZ * drive + (random() - 0.5) * 20
      grain.maxLife[i] = (3.2 + random() * 4.2) * 5.0
    end
    -- 8.2.10: leaf size is an intrinsic physical property for the full leaf
    -- lifetime. Do NOT bake spawn distance into grain.size. The draw path below
    -- already derives presentation scale from the leaf's CURRENT eye distance,
    -- so a leaf born far away must grow normally as it blows toward the player
    -- (and shrink normally as it moves away). The old spawnNear multiplier made
    -- far-born leaves permanently 2.45x smaller than equally seeded near-born
    -- leaves even after both reached the same current position.
    grain.size[i] = leafScale
    -- Opacity is intrinsic too. Current-distance fading is applied in the draw
    -- path, so spawn radius must not permanently mark a far-born leaf as dim.
    grain.a[i] = 0.51 + random() * 0.35
    -- spin used as tumble rate seed (draw path)
    grain.spin[i] = 0.35 + random() * 0.65
  else
    -- Hail (kind 1) and anything unmapped: hard, fast, straight down.
    local hailBase = precipDeckY or (py + 24*WP._cloudHeightScale())
    local hailSpan = precipDeckSpan or 110
    grain.y[i] = hailBase + random() * hailSpan
    grain.vx[i] = windX * (6 + random() * 10)
    grain.vy[i] = -(34 + random() * 26)
    grain.vz[i] = windZ * (6 + random() * 10)
    local hailDrop = max(1.0, grain.y[i] - (py - GROUND_DROP))
    grain.maxLife[i] = (hailDrop / max(1.0, -grain.vy[i])) * 1.15 + 0.25
    -- Smaller than a snowflake and much more opaque: a hailstone is a small
    -- dense pellet, not a big soft smudge. The size gap is deliberate -- it is
    -- half of what makes hail readable as hail next to snow, the other half
    -- being the hard edge (see the UV inset in drawGrains).
    grain.size[i] = (0.16 + random() * 0.20) * (0.6 + near * 0.7)
    grain.a[i] = 0.70 + random() * 0.30
  end

  -- 8.0.1 RAM pass: every tumble/wobble coefficient below is a pure
  -- function of the already-stored seed/spin. Do not store eight duplicate
  -- per-particle arrays; derive the identical numbers in the hot path.
  local hvx, hvz = grain.vx[i] or 0, grain.vz[i] or 0
  grain.hSpeed[i] = sqrt(hvx * hvx + hvz * hvz)

  -- Hail and ash also originate at the cloud bank. Prime only the first
  -- activation/reassignment of a slot so the storm is immediately populated
  -- from cloud to ground; normal recycling always restarts visibly at the bank.
  if primeColumn and (kind == 1 or kind == 4) then
    local floorY = py - GROUND_DROP
    local drop = max(1.0, grain.y[i] - floorY)
    local frac = random() * 0.88
    local fallSpeed = max(1.0, -(grain.vy[i] or -1))
    local age = (drop / fallSpeed) * frac
    grain.life[i] = min((grain.maxLife[i] or age) * 0.88, age)
    grain.y[i] = grain.y[i] - drop * frac
    grain.x[i] = grain.x[i] + (grain.vx[i] or 0) * age * 0.55
    grain.z[i] = grain.z[i] + (grain.vz[i] or 0) * age * 0.55
  end
end

-- ---------------------------------------------------------------------------
-- WEATHER CLASSIFICATION
-- ---------------------------------------------------------------------------
-- The old inline check missed every FROST* variant, ICEBOUND and WHITEOUT —
-- those weathers produced literally zero 3D snow even once the module loaded.
-- Exact ids first, then prefixes, so a new FROSTWHATEVER is snowy by default.
local SNOW_TARGET = {
  BLIZZARD = 2.2, WHITEOUT = 2.4, THUNDERSNOW = 3.0, DRAGONSTORM = 1.8,
  SNOW = 1.9, SNOW_LIGHT = 1.9, SNOWY = 1.9, TSNOW = 2.0,
  -- HAIL removed from this table. It used to request a snow target of 0.6, so
  -- hail weather rained snowflakes AND hailstones at once -- which muddies
  -- exactly the distinction being asked for. Hail is ice pellets; it is not
  -- snowfall. SLEET keeps its snow because sleet genuinely is part snow.
  ICEBOUND = 1.6, SLEET = 0.5,
}

local function snowyTarget(wxId)
  if not wxId or wxId == "" then return 0 end
  local t = SNOW_TARGET[wxId]
  if t then return t end
  if wxId:find("SNOW", 1, true) then return 1.4 end
  if wxId:sub(1, 5) == "FROST" then return 1.2 end
  if wxId:sub(1, 3) == "ICE" then return 1.2 end
  return 0
end

-- Shared classifiers. 4.33.0 rebuilt these closures in both update() and draw()
-- every frame. Their answers depend only on the weather id, so keep one copy.
local function isSnowyWx(id)
  if not id or id == "" then return false end
  if id:find("SNOW", 1, true) then return true end
  return id == "BLIZZARD" or id == "THUNDERSNOW" or id == "SLEET"
      or id == "DRAGONSTORM" or id == "WHITEOUT"
end

local function isRainOnlyWx(id)
  if not id or id == "" then return false end
  if id:find("RAIN", 1, true) then return true end
  return id == "STORM" or id == "THUNDERSTORM" or id == "GALE"
      or id == "DRIZZLE" or id == "PRIMAL" or id == "PRIMAL_RAIN"
      or id == "HEAVY" or id == "HEAVY_RAIN" or id == "PSYSTORM"
end

-- Weather FX id/channel recovery. Rain can survive a stale bridge because the
-- embedded 3D rain profile already carries rainIntensity. The other families
-- historically relied much more heavily on CinematicAtmos's notify/channel
-- handoff, so one stale callback could leave snow/hail/sand/ash/leaves with a
-- zero target even though Weather FX itself was correctly set to that weather.
-- Read the shared namespace id directly and independently rebuild missing
-- channels from Types before particle counts are calculated.
local _Types = nil
local function typesModule()
  if _Types then return _Types end
  local ok, m = V.safeCall(V.require, "Types")
  if ok and m then _Types = m end
  return _Types
end

local function authoritativeWeatherId(weather)
  local id = tostring((weather and (weather.wxId or weather.id)) or ""):upper()
  if id == "" or id == "NIL" or id == "NONE" then
    id = tostring((V and V.weatherFxId) or ""):upper()
  end
  if id == "NIL" or id == "NONE" or id == "NONE_WEATHER" then id = "" end
  return id
end

local function resolveFamilyIntensities(weather, wxId)
  weather = weather or {}
  wxId = tostring(wxId or authoritativeWeatherId(weather)):upper()
  local rainI = tonumber(weather.rainIntensity) or 0
  local snowI = tonumber(weather.snowIntensity) or 0
  local hailI = tonumber(weather.hailIntensity) or 0
  local sandI = tonumber(weather.sandIntensity) or 0
  local ashI = tonumber(weather.ashIntensity) or 0
  local debrisI = tonumber(weather.debrisIntensity) or 0
  -- CinematicAtmos marks a bag after it has already rebuilt the catalogue
  -- channels AND applied the user's INTENSITY/SAND/DUST controls. Compatibility
  -- floors must not overwrite those scaled values or SOFT becomes NORMAL again.
  local resolvedByAtmos = weather._wxChannelsResolved == true

  local T = typesModule()
  local def = T and T.byId and T.byId[wxId] or nil
  -- A CinematicAtmos-resolved bag contains the exact live WeatherState channel
  -- values, including intentional zeros early/late in a natural handoff. Do not
  -- "repair" those zeros from the full-strength catalogue or the strict-3D path
  -- will pop precipitation on before the synoptic planner requests it.
  if not resolvedByAtmos and def and T.channel then
    local function fill(cur, key)
      if cur > 0.02 then return cur end
      local ok, v = V.safeCall(T.channel, def, key)
      v = ok and tonumber(v) or 0
      return (v and v > 0) and v or cur
    end
    if not weather._rainExplicitOff then rainI = fill(rainI, "rain") end
    if not weather._snowExplicitOff then snowI = fill(snowI, "snow") end
    hailI = fill(hailI, "hail")
    if not weather._sandExplicitOff then sandI = fill(sandI, "sand") end
    ashI = fill(ashI, "ash")
    debrisI = fill(debrisI, "debris")
  end

  -- Hard authored floors guarantee the named core families spawn even if a
  -- compatibility host temporarily cannot resolve Types. These match the 3D
  -- tuning in CinematicAtmos rather than inventing a second visual recipe.
  if not resolvedByAtmos then
    if (not weather._snowExplicitOff) and isSnowyWx(wxId) and wxId ~= "HAIL" then
      snowI = max(snowI, snowyTarget(wxId))
    end
    if wxId == "HAIL" then
      hailI = max(hailI, 1.25)
    elseif wxId == "SLEET" then
      hailI = max(hailI, 0.45)
    end
    if not weather._sandExplicitOff then
      if wxId == "SANDSTORM" then sandI = max(sandI, 2.35)
      elseif wxId == "DUSTSTORM" then sandI = max(sandI, 1.20)
      elseif wxId == "DRAGONSTORM" then sandI = max(sandI, 0.55) end
    end
    if wxId == "ASHFALL" then ashI = max(ashI, 1.45) end
    if wxId == "GALE" or wxId == "STRONG_WINDS" or wxId == "BRAWL_WIND"
        or wxId == "FLOCKSTORM" then
      debrisI = max(debrisI, 1.15)
    elseif wxId == "DRAGONSTORM" then
      debrisI = max(debrisI, 0.45)
    end
  end
  -- Compatibility-only id cleanups. Exact live bags are already authoritative
  -- and may intentionally carry outgoing precipitation while the target id is
  -- CLEAR/SUNNY, or mixed families during a phase-change handoff.
  if not resolvedByAtmos and wxId == "HAIL" then snowI, rainI = 0, 0 end
  if weather._sandExplicitOff then sandI = 0 end
  if weather._snowExplicitOff then snowI = 0 end
  if weather._rainExplicitOff then rainI = 0 end

  if not resolvedByAtmos and (wxId == "" or wxId == "CLEAR" or wxId == "SUNNY" or wxId == "OFF"
      or wxId == "HEATWAVE" or wxId == "HARSH_SUN") then
    rainI, snowI, hailI, sandI, ashI, debrisI = 0, 0, 0, 0, 0, 0
  end

  -- Mutate the per-frame weather bag so update() and draw() cannot disagree.
  weather.wxId = wxId
  weather.rainIntensity = rainI
  weather.snowIntensity = snowI
  weather.hailIntensity = hailI
  weather.sandIntensity = sandI
  weather.ashIntensity = ashI
  weather.debrisIntensity = debrisI
  weather._wpChannelsResolved = true
  return rainI, snowI, hailI, sandI, ashI, debrisI, wxId
end

-- ---------------------------------------------------------------------------
-- CACHED HOST QUERIES
-- ---------------------------------------------------------------------------
-- Module objects are stable for the lifetime of a loaded mod. Cache successful
-- private-loader resolves so menu/state polling does not allocate protected-call closures
-- or traverse the loader repeatedly. Failed early resolves are retried later.
local _Settings, _Quality, _Scene, _Wind, _LeafPhysics, _SnowPack, _SnowSurfacePaint, _HostVoxelScene, _HostTileShape = nil, nil, nil, nil, nil, nil, nil, nil, nil
settingsModule = function()
  if _Settings then return _Settings end
  local ok, m = V.safeCall(V.require, "Settings")
  if ok and m then _Settings = m end
  return _Settings
end

-- 8.2.9: fixed WEATHER STRENGTH scales the actual logical particle budget.
-- NORMAL is the established quality-tier budget; SOFT uses 45% of it and
-- HEAVY may use 150%. AUTO remains driven by the eased per-family channels.
function WP._fixedPopulationStrength()
  local S=settingsModule()
  if not (S and S.get) then return 1,false end
  local ok,k=V.safeCall(S.get,"intensity")
  if not ok then return 1,false end
  k=tostring(k or ""):lower()
  if k=="soft" then return .45,true end
  if k=="normal" then return 1.0,true end
  if k=="heavy" then return 1.50,true end
  return 1,false
end
function WP._cloudHeightScale()
  local S=settingsModule()
  local v=S and S.cloudHeightScale and S.cloudHeightScale() or 1.5
  return max(1.0,min(1.5,tonumber(v) or 1.5))
end
function configModule()
  local ok, m = V.safeCall(V.require, "Config")
  if ok and m then return m end
  return nil
end
function WP._frontsEnabled()
  local C=configModule()
  if C and C.get then
    local ok,cfg=V.safeCall(C.get)
    if ok and type(cfg)=='table' and type(cfg.fronts)=='table' and cfg.fronts.enabled~=nil then return cfg.fronts.enabled~=false end
  end
  local S=settingsModule()
  if S and S.get then
    local ok,v=V.safeCall(S.get,'fronts')
    if ok then
      if v=='off' then return false end
      if v=='on' then return true end
    end
  end
  return true
end
function WP._voxelRenderDistance(meta)
  local vox=meta and meta.Voxel3D
  if not vox then return nil end
  local f=tonumber(vox.far or (vox.camera and vox.camera.far))
  if f and f>80 then return f end
  return nil
end
qualityModule = function()
  if _Quality then return _Quality end
  local ok, m = V.safeCall(V.require, "Quality")
  if ok and m then _Quality = m end
  return _Quality
end
sceneModule = function()
  if _Scene then return _Scene end
  local ok, m = V.safeCall(V.require, "Scene")
  if ok and m then _Scene = m end
  return _Scene
end
function WP._battleModule()
  if WP._battleCache then return WP._battleCache end
  local ok,m=V.safeCall(V.require,"Battle")
  if ok and m then WP._battleCache=m end
  return WP._battleCache
end
windModule = function()
  if _Wind then return _Wind end
  local ok, m = V.safeCall(V.require, "WindEngine")
  if ok and m then _Wind = m end
  return _Wind
end
leafPhysicsModule = function()
  if _LeafPhysics then return _LeafPhysics end
  local ok, m = V.safeCall(V.require, "LeafPhysics")
  if ok and m then _LeafPhysics = m end
  return _LeafPhysics
end
snowPackModule = function()
  if _SnowPack then return _SnowPack end
  local ok,m=V.safeCall(V.require,"SnowPack")
  if ok and m then _SnowPack=m end
  return _SnowPack
end
WP._snowSurfacePaintModule = function()
  if _SnowSurfacePaint then return _SnowSurfacePaint end
  local ok,m=V.safeCall(V.require,"SnowSurfacePaint")
  if ok and m then _SnowSurfacePaint=m end
  return _SnowSurfacePaint
end
hostVoxelSceneModule = function()
  if _HostVoxelScene then return _HostVoxelScene end
  -- `V` here is the private VOXEL namespace, whose loader resolves genuine
  -- host extensions before Weather FX root modules. LeafPhysics itself lives
  -- in the root namespace, so it cannot safely discover VoxelScene on its own.
  local ok, m = V.safeCall(V.require, "VoxelScene")
  if ok and m and type(m.groundAt)=="function" then _HostVoxelScene = m end
  return _HostVoxelScene
end
hostTileShapeModule = function()
  if _HostTileShape then return _HostTileShape end
  local ok,m=V.safeCall(V.require,"TileShape")
  if ok and m and type(m.forMap)=="function" then _HostTileShape=m end
  return _HostTileShape
end
WP._hostStructuresModule = function()
  if WP._hostStructuresCache then return WP._hostStructuresCache end
  -- Exact visible round-tree/canopy/planter hulls.  SnowPack reads only the
  -- cached stamp quads produced by the host; Weather FX never mutates them.
  local ok,m=V.safeCall(V.require,"Structures")
  if ok and m and type(m.forMap)=="function" then WP._hostStructuresCache=m end
  return WP._hostStructuresCache
end

function WP._mesoscaleModule()
  if WP._mesoscaleCache then return WP._mesoscaleCache end
  local ok,m=V.safeCall(V.require,"MesoscaleField")
  if ok and m then WP._mesoscaleCache=m end
  return WP._mesoscaleCache
end
function WP._proceduralSnowModule()
  -- Private Weather FX module: cache only successful resolves. A failed early
  -- resolve is retried later, matching the other runtime-safe module helpers.
  if snow.proceduralModule then return snow.proceduralModule end
  local ok,m=V.safeCall(V.require,"ProceduralSnowField")
  if ok and m then snow.proceduralModule=m end
  return snow.proceduralModule
end
function WP._proceduralPrecipModule()
  if grain.proceduralModule then return grain.proceduralModule end
  local ok,m=V.safeCall(V.require,"ProceduralPrecipField")
  if ok and m then grain.proceduralModule=m end
  return grain.proceduralModule
end
function WP.preflight(Voxel3D,focus,weather,meta)
  if not (Voxel3D and Voxel3D.vp and focus) then return false end
  weather=weather or {};meta=meta or {}
  do
    local m=meta.map or (meta.state and meta.state.map)
    local id=m and tostring(m.id or (m.def and (m.def.id or m.def.name)) or m) or nil
    meta._mapChanged=(id~=nil and WP._lastMapId~=nil and id~=WP._lastMapId) and true or false
  end
  -- X/Z use the live gameplay player immediately after a map transfer. This
  -- prevents one stale voxel snapshot from delaying the weather field until the
  -- player takes a step.
  local x,y,z=tonumber(focus[1]) or 0,tonumber(focus[2]) or 0,tonumber(focus[3]) or 0
  local lp=meta.player
  if lp and tonumber(lp.px) and tonumber(lp.py) then x,z=tonumber(lp.px)+8,tonumber(lp.py)+8 end
  local a=WP._preflightAnchor or {0,0,0};WP._preflightAnchor=a;a[1],a[2],a[3]=x,y,z
  local wx=authoritativeWeatherId(weather)
  local rainI,snowI,hailI,sandI,ashI,debrisI
  rainI,snowI,hailI,sandI,ashI,debrisI,wx=resolveFamilyIntensities(weather,wx)
  local eye=Voxel3D.eye or Voxel3D.player or a
  local voxelFar=WP._voxelRenderDistance(meta) or tonumber(Voxel3D.far) or 600
  local fronts=WP._frontsEnabled()
  local scale=1
  do
    local S=settingsModule()
    if S and S.weatherRenderDistanceScale then
      local ok,v=V.safeCall(S.weatherRenderDistanceScale)
      if ok and tonumber(v) then scale=max(.01,min(1,tonumber(v))) end
    end
  end
  -- 8.1.92: snow coverage follows the live voxel far plane even while
  -- WEATHER FRONTS is ON. Regional/front logic may vary density/patchiness,
  -- but it may not shrink the physical snow volume into an outrunnable disk.
  -- The player-facing 3D WEATHER DISTANCE remains an intentional weather-only
  -- reduction; its default 100% is exactly the host render distance.
  local snowFar=max(SNOW_MIN_R,voxelFar*scale)
  local precipFar=fronts and voxelFar or max(4,voxelFar*scale)
  local deckY=tonumber(meta.deckY) or (y+SNOW_CEIL*WP._cloudHeightScale())
  local deckSpan=max(1,tonumber(meta.deckSpan) or SNOW_CEIL_SPAN)
  local bottom=y-GROUND_DROP
  local any=false
  if snowI>.02 then
    local PS=WP._proceduralSnowModule();local st=PS and PS.stats and PS.stats() or nil
    if PS and PS.reanchor and meta._mapChanged then V.safeCall(PS.reanchor,a,snowFar) end
    if PS and PS.probe and (not st or (not st.proven and not st.failed)) then
      local ok,v=V.safeCall(PS.probe,Voxel3D,{eye=eye,focus=a,wind={snow.lastWindX or 0,snow.lastWindZ or 0},nearRadius=1.5,farRadius=snowFar,topY=deckY,bottomY=bottom,span=deckSpan,time=simTime,intensity=snowI,tint={1,1,1},ball=false,uniformField=(not fronts)})
      any=any or (ok and v==true)
    end
  end
  if rainI>.02 or hailI>.02 or sandI>.02 or ashI>.02 then
    local PP=WP._proceduralPrecipModule();local st=PP and PP.stats and PP.stats() or nil
    if PP and PP.reanchor and meta._mapChanged then V.safeCall(PP.reanchor,a,max(4,precipFar)) end
    if PP and PP.probe and (not st or (not st.proven and not st.failed)) then
      local kind=(hailI>.02 and "hail") or (sandI>.02 and "sand") or (ashI>.02 and "ash") or "rain"
      local ok,v=V.safeCall(PP.probe,Voxel3D,{kind=kind,eye=eye,focus=a,wind={grain.lastWindX or 0,grain.lastWindZ or 0},nearRadius=1.5,farRadius=max(4,precipFar),topY=deckY,bottomY=(rain.fieldBottomY or (bottom-32)),span=deckSpan,time=simTime,intensity=max(rainI,hailI,sandI,ashI),tint={1,1,1},uniformField=(not fronts),worldGrid=((not fronts) and kind=='rain')})
      any=any or (ok and v==true)
    end
  end
  return any
end
-- These used to be a `V.safeCall(function() ... end)` per frame: a fresh closure
-- every update just to read a number that changes on a menu press.
local qBudget, qAt = { worldPrecip=1.0, worldRadiusCap=750, _qualityRev=-1, _capRev=-1 }, -1
local function qualityBudget()
  -- Quality can change from the options page while weather is live. Ordinary
  -- frames keep the cheap 0.25s cache, but an actual QUALITY/PARTICLE CAP edit
  -- invalidates it synchronously so the next precipitation update uses the new
  -- budget instead of looking stuck on the previous tier.
  local S=settingsModule()
  local qr=(S and S.keyRevision and S.keyRevision("quality")) or qBudget._qualityRev
  local cr=(S and S.keyRevision and S.keyRevision("particleCap")) or qBudget._capRev
  if qr==qBudget._qualityRev and cr==qBudget._capRev and simTime - qAt < 0.25 then return qBudget end
  qBudget._qualityRev,qBudget._capRev=qr,cr
  qAt = simTime
  local Q = qualityModule()
  if Q and Q.budget then
    local b = Q.budget(1)
    if b then b._qualityRev=qr;b._capRev=cr;qBudget = b end
  end
  return qBudget
end

-- Battle ownership must be frame-live. A former 1-second cache let the
-- overworld precipitation volume survive into the battle transition long enough
-- for the battle camera/focus jump to re-anchor the whole snow pool. The player
-- saw that as a sudden snow dump, then a stop when the cache finally noticed
-- the battle, then a second start from BattleDraw.
--
-- Battle.current() flips on the battle.started event before the battle canvas is
-- necessarily the visible Scene state, so it is the earliest authoritative
-- signal. Scene remains a fallback for host variants that expose only the state
-- stack. Both reads are cached module/table accesses; there is no expensive
-- loader traversal per frame.
local inBattle=false
local function battleActive()
  local B=WP._battleModule()
  if B and B.current and B.current() then inBattle=true; return true end
  local Sc=sceneModule()
  inBattle=(Sc and Sc.now and Sc.now.visible=="battle") and true or false
  return inBattle
end

local fpv, fpvAt = false, -1
local function firstPerson()
  if simTime - fpvAt < 1.0 then return fpv end
  fpvAt = simTime
  local S = settingsModule()
  if S and S.isFirstPerson then fpv = S.isFirstPerson() and true or false end
  return fpv
end

-- ---------------------------------------------------------------------------
-- UPDATE
-- ---------------------------------------------------------------------------
-- World Y for rain/snow ground marks.
-- When focus sits clearly below the eye, treat it as feet and place marks
-- just above it. When focus IS the eye (no player), drop by GROUND_DROP so
-- marks land on the floor instead of floating at head/ceiling height.
local function depositGroundY(focusY, eyeY)
  focusY = tonumber(focusY) or 0
  eyeY = tonumber(eyeY)
  if eyeY and (eyeY - focusY) > 4.0 then
    return focusY + 0.3
  end
  return focusY - GROUND_DROP + 0.3
end

-- LuaJIT 2.1 permits at most 60 upvalues per Lua function. WP.update used to
-- capture more than that directly from this module, which made WorldPrecip fail
-- to compile on the real LÖVE/LuaJIT host while headless Lua 5.3 tests still
-- looked healthy. Group immutable update dependencies behind one table, then
-- shadow them as ordinary function locals. This changes no simulation values;
-- it only keeps the closure below the VM's hard compiler limit.
local UPDATE_CONST = {
  floor=floor, abs=abs, min=min, max=max, sin=sin, cos=cos, random=random, PI2=PI2,
  RAIN_MAX=RAIN_MAX, RAIN_PER_TILE=RAIN_PER_TILE, GRAIN_MAX=GRAIN_MAX, HAIL_MAX=HAIL_MAX, TILE=TILE,
  SNOW_MAX=SNOW_MAX, SNOW_PER_TILE=SNOW_PER_TILE, SNOW_RADIUS_MIN=SNOW_RADIUS_MIN,
  SNOW_RADIUS_MAX=SNOW_RADIUS_MAX, SNOW_FAR_FRACTION=SNOW_FAR_FRACTION,
  FACE_R2=FACE_R2, FACE_LIFE=FACE_LIFE, WET_LIFE=WET_LIFE,
  -- Keep snow/leaf integration dependencies behind one table upvalue.
  -- WorldPrecip.update is already a very large hot-path function and LuaJIT
  -- has a hard 60-upvalue compiler limit. Adding SnowPack must not make the
  -- actual host unable to compile the function.
  snowPackModule=snowPackModule,
  hostVoxelSceneModule=hostVoxelSceneModule,
  hostTileShapeModule=hostTileShapeModule,
  ensureGSnow=ensureGSnow, interactionLoader=WP._interactionPrecip,
  gsnow=gsnow, foot=foot,
  GSNOW_MAX=GSNOW_MAX, FOOT_MAX=FOOT_MAX,
}

function WP.update(dt, focus, weather, streamMeta)
  local C = UPDATE_CONST
  local floor, abs, min, max, sin, cos, random, PI2 =
    C.floor, C.abs, C.min, C.max, C.sin, C.cos, C.random, C.PI2
  local RAIN_MAX, RAIN_PER_TILE, GRAIN_MAX, HAIL_MAX, TILE =
    C.RAIN_MAX, C.RAIN_PER_TILE, C.GRAIN_MAX, C.HAIL_MAX, C.TILE
  local SNOW_MAX, SNOW_PER_TILE, SNOW_RADIUS_MIN, SNOW_RADIUS_MAX, SNOW_FAR_FRACTION =
    C.SNOW_MAX, C.SNOW_PER_TILE, C.SNOW_RADIUS_MIN, C.SNOW_RADIUS_MAX, C.SNOW_FAR_FRACTION
  local FACE_R2, FACE_LIFE, WET_LIFE = C.FACE_R2, C.FACE_LIFE, C.WET_LIFE
  local snowPackModule, hostVoxelSceneModule, hostTileShapeModule, ensureGSnow =
    C.snowPackModule, C.hostVoxelSceneModule, C.hostTileShapeModule, C.ensureGSnow
  local WorldInteractionPrecip = C.interactionLoader()
  local gsnow, foot, GSNOW_MAX, FOOT_MAX =
    C.gsnow, C.foot, C.GSNOW_MAX, C.FOOT_MAX
  if not focus then return end
  local inputDt = tonumber(dt) or 0
  if inputDt < 0 then inputDt = 0 end
  WP._animationPaused = (inputDt <= 0)
  local rainDt = WP._rainFrameDt(inputDt)
  dt = inputDt
  if dt > 0.1 then dt = 0.1 end
  simTime = simTime + dt

  -- Stand the overworld precipitation field down BEFORE reading the battle
  -- camera/focus. Keep the existing world pools and lastStreamFocus untouched
  -- so battle entry cannot shift/recycle them and battle exit resumes from the
  -- same world-space field instead of spawning a second burst.
  if battleActive() then return end

  local px = focus[1] or 0
  local py = focus[2] or 0
  local pz = focus[3] or 0
  streamMeta = streamMeta or {}
  -- Gameplay player position is authoritative for world X/Z, especially on the
  -- first frame after a map transition when Voxel3D.player can still contain
  -- the previous map snapshot. World Y remains the host voxel value.
  do
    local lp=streamMeta.player
    if lp and tonumber(lp.px) and tonumber(lp.py) then px,pz=tonumber(lp.px)+8,tonumber(lp.py)+8 end
  end
  do
    local m=streamMeta.map or (streamMeta.state and streamMeta.state.map)
    local id=m and tostring(m.id or (m.def and (m.def.id or m.def.name)) or m) or nil
    WP._mapJustChanged=(id~=nil and WP._lastMapId~=nil and id~=WP._lastMapId) and true or false
    if id~=nil then WP._lastMapId=id end
    streamMeta._mapChanged=WP._mapJustChanged
  end
  precipDeckY = tonumber(streamMeta.deckY)
  precipDeckSpan = tonumber(streamMeta.deckSpan)
  if precipDeckSpan and precipDeckSpan < 1 then precipDeckSpan = 1 end
  local streamKind = tostring(streamMeta.anchorKind or "legacy")
  local eyeY = lastEye and lastEye[2] or nil
  local groundMarkY = depositGroundY(py, eyeY)
  -- Map / warp jump: carry the weather field with the player so precipitation
  -- does not all recycle in one frame and leave a blank sky for a beat.
  if lastStreamFocus then
    local jx = px - (lastStreamFocus[1] or px)
    local jy = py - (lastStreamFocus[2] or py)
    local jz = pz - (lastStreamFocus[3] or pz)
    local jump2 = jx * jx + jz * jz
    local jumpThresh = (STREAM_RADIUS * 0.45) * (STREAM_RADIUS * 0.45)
    -- Never carry the whole storm merely because the host switched which
    -- camera/player point it exposes. Camera-mode/source changes are not world
    -- teleports. Re-anchor first; only a stable anchor source may carry pools.
    local sameAnchorKind = (lastStreamKind == nil or lastStreamKind == streamKind)
    if sameAnchorKind and (WP._mapJustChanged or jump2 > jumpThresh or math.abs(jy) > 40) then
      local function shiftPool(pool, n, shiftY)
        if not pool or not pool.x then return end
        n = n or pool.active or pool.n or 0
        for i = 1, n do
          if pool.x[i] then pool.x[i] = pool.x[i] + jx end
          if shiftY and pool.y[i] then pool.y[i] = pool.y[i] + jy end
          if pool.z[i] then pool.z[i] = pool.z[i] + jz end
          if shiftY and pool.y0 and pool.y0[i] then pool.y0[i] = pool.y0[i] + jy end
          if shiftY and pool.baseY and pool.baseY[i] then pool.baseY[i] = pool.baseY[i] + jy end
          if shiftY and pool.edgeW and pool.edgeW[i] then pool.edgeW[i] = pool.edgeW[i] + jy end
          if shiftY and pool.edgeE and pool.edgeE[i] then pool.edgeE[i] = pool.edgeE[i] + jy end
          if shiftY and pool.edgeN and pool.edgeN[i] then pool.edgeN[i] = pool.edgeN[i] + jy end
          if shiftY and pool.edgeS and pool.edgeS[i] then pool.edgeS[i] = pool.edgeS[i] + jy end
        end
      end
      -- Falling particles move with the player in full 3D.
      shiftPool(rain, rain.simActive or rain.active, true)
      shiftPool(snow, snow.simActive or snow.active, true)
      shiftPool(grain, grain.active, true)
      -- Ground marks stay on the floor: only slide in XZ on a real horizontal
      -- warp. Shifting their Y with the camera/eye made snow "splash" ride up
      -- to ceiling height and follow the view.
      local shiftGroundY = (jump2 > jumpThresh) and (math.abs(jy) > 40)
      shiftPool(wet, wet.active, shiftGroundY)
      shiftPool(gsnow, gsnow.active, shiftGroundY)
    end
  end
  if lastStreamFocus then
    lastStreamFocus[1], lastStreamFocus[2], lastStreamFocus[3] = px, py, pz
  else
    lastStreamFocus = { px, py, pz }
  end
  lastStreamKind = streamKind
  if WP._mapJustChanged then
    local a=WP._mapAnchorScratch or {0,0,0};WP._mapAnchorScratch=a;a[1],a[2],a[3]=px,py,pz
    local PS=WP._proceduralSnowModule();if PS and PS.reanchor then V.safeCall(PS.reanchor,a,SNOW_STREAM_RADIUS) end
    local PP=WP._proceduralPrecipModule();if PP and PP.reanchor then V.safeCall(PP.reanchor,a,STREAM_RADIUS) end
  end
  weather = weather or {}
  local wxId = authoritativeWeatherId(weather)
  local rainI, snowI, hailI, sandI, ashI, debrisI
  rainI, snowI, hailI, sandI, ashI, debrisI, wxId = resolveFamilyIntensities(weather, wxId)
  weather._populationStrength,weather._populationStrengthFixed=WP._fixedPopulationStrength()
  local frontsOn = WP._frontsEnabled()
  WP._uniformPrecipField = not frontsOn

  -- 8.1.76 fronts-OFF weather identity authority. The frame-local cinematic
  -- weather bag can briefly publish CLEAR/zero while the host changes player
  -- pose/elevation (most visibly while hopping a ledge). That is presentation
  -- state, not a new weather decision. When fronts are OFF, prefer the player's
  -- explicit WEATHER selection; otherwise prefer the root Weather FX id while
  -- no authored transition is active. This prevents a ledge step or pose frame
  -- from reclassifying an active rainstorm as clear and tearing down the stream.
  if not frontsOn and weather._rainExplicitOff~=true and weather._transitionActive~=true then
    local owner=nil
    local S=settingsModule()
    if S and S.manualWeatherSelected then
      local ok,v=V.safeCall(S.manualWeatherSelected)
      if ok and v then owner=tostring(v):upper() end
    end
    if not owner then
      local root=tostring((V and V.weatherFxId) or ''):upper()
      if root~='' and root~='NIL' and root~='NONE' and root~='NONE_WEATHER' then owner=root end
    end
    if owner and isRainOnlyWx(owner) and not isRainOnlyWx(wxId) then
      wxId=owner
      weather.wxId=owner
    end
  end

  -- 8.1.75/8.1.76 fronts-OFF continuity latch. A manually/authored active rain weather
  -- must not be deallocated because one live channel snapshot briefly reports
  -- zero while the player walks. Preserve the last real nonzero rain amount for
  -- the same rain-family weather id; explicit RAIN AMOUNT=OFF, a real weather-id
  -- change, or an authored transition still owns shutdown. This is deliberately
  -- fronts-OFF only: fronts ON retains physical regional onset/decay.
  if not frontsOn then
    local rainFamily=isRainOnlyWx(wxId)
    local explicitOff=weather._rainExplicitOff==true
    local transitioning=weather._transitionActive==true
    if explicitOff or not rainFamily then
      rain.stableIntensity=nil;rain.stableWx=nil
    elseif rainI>.02 then
      rain.stableIntensity=rainI;rain.stableWx=wxId
    elseif not transitioning and rain.stableWx==wxId and (tonumber(rain.stableIntensity) or 0)>.02 then
      rainI=tonumber(rain.stableIntensity) or rainI
      weather.rainIntensity=rainI
    elseif not transitioning then
      -- First frame of an already-selected rain id before the live channel bag
      -- has caught up. Keep allocation alive at the smallest visible amount; as
      -- soon as the real channel arrives it replaces this floor and is latched.
      rainI=.021
      weather.rainIntensity=rainI
    end
  else
    rain.stableIntensity=nil;rain.stableWx=nil
  end

  -- Mesoscale precipitation makes the physical near shell represent the band
  -- the player is actually standing under. Far-field shaders reconstruct the
  -- broader rain/snow pattern independently, so this does not add particles or
  -- per-drop climate queries.
  do
    -- WEATHER FRONTS OFF is a uniform-weather ownership mode. Do not let the
    -- mesoscale shower-band sampler turn rain/snow/hail down as the player
    -- walks through world-space noise cells; that made precipitation visibly
    -- start and stop with movement even though the weather itself was steady.
    -- Fronts ON keeps the authored regional/banded modulation unchanged.
    if frontsOn then
      local M=WP._mesoscaleModule()
      local ms=M and (not M.ready or M.ready()) and M.peek and M.peek() or nil
      local localScale=ms and tonumber(ms.precipScale) or 1
      if localScale then
        localScale=max(.02,min(1.15,localScale))
        local baseRainI,baseSnowI,baseHailI=rainI,snowI,hailI
        rainI,snowI,hailI=rainI*localScale,snowI*localScale,hailI*localScale
        -- A mesoscale trough may thin an active front, but must not toggle the
        -- precipitation engine off merely by crossing the 0.02 allocation
        -- threshold while the authored weather channel itself remains active.
        if baseRainI>.02 and rainI<=.02 then rainI=.021 end
        if baseSnowI>.02 and snowI<=.02 then snowI=.021 end
        if baseHailI>.02 and hailI<=.02 then hailI=.021 end
      end
    end
  end
  -- Only true snow weathers get flakes; rain/storm ids hard-gate snow.
  if isRainOnlyWx(wxId) or wxId == "HAIL" then
    snowI = 0
  elseif isSnowyWx(wxId) then
    -- Exact live WeatherState zero (including SNOW INTENSITY OFF) is an
    -- instruction, not missing data. Only compatibility bags without live
    -- channel authority may recover a named-weather snow floor.
    if snowI <= 0.02 and weather._wxChannelsResolved ~= true and weather._snowExplicitOff ~= true then
      snowI = snowyTarget(wxId)
    end
  elseif snowI > 0.02 then
    -- wxId missing but intensity present: keep snow (bag was snowy profile)
    snowI = snowI
  else
    snowI = 0
  end
  -- precipDeckY/precipDeckSpan were supplied by CinematicAtmos from the same
  -- deck geometry used for visible 3D clouds. Do not derive a second camera-
  -- relative ceiling here; all vertical precipitation families share that bank.

  local windS = tonumber(weather and weather.rainWind) or 1
  if snowI > 0 then
    windS = tonumber(weather and weather.snowWind) or windS
  end
  -- World wind along XZ. Weather FX 4.35.18 replaces the historical fixed
  -- {0.55,0.25} lane with the shared WindEngine. This remains camera-
  -- independent, but can now veer, lull and gust continuously with weather.
  local windX, windZ = 0.55 * windS, 0.25 * windS
  local WE = windModule()
  if WE and WE.vector then
    local ok, x, z = V.safeCall(WE.vector, windS)
    if ok and tonumber(x) and tonumber(z) then windX, windZ = x, z end
  end
  -- Weather FX 7 local flow field bends/shelters the authoritative global wind
  -- around biome/city context while remaining fully world-space.
  do
    local okF,F=V.safeCall(V.require,"WindFlow")
    if okF and F and F.vector then local ok,x,z=V.safeCall(F.vector,px,pz,windS); if ok and tonumber(x) and tonumber(z) then windX,windZ=x,z end end
  end
  local windMag = math.sqrt(windX*windX + windZ*windZ)
  local windDirX, windDirZ = 0, 0
  if windMag > 1e-5 then windDirX, windDirZ = windX/windMag, windZ/windMag end

  local qb = qualityBudget()
  local q = tonumber(qb.worldPrecip) or 1.0
  local weatherDistanceScale = 1.0
  do
    local S=settingsModule()
    if S and S.weatherRenderDistanceScale then
      local ok,v=V.safeCall(S.weatherRenderDistanceScale)
      if ok and tonumber(v) then weatherDistanceScale=max(0.01,min(1.0,tonumber(v))) end
    end
  end
  -- QUALITY OWNS DENSITY AND HARD PARTICLE BUDGETS. Regional rain/hail may
  -- additionally use the quality radius cap, but 8.1.92 makes snow reach a
  -- render-distance contract: low tiers may draw fewer flakes, never a smaller
  -- 100% snow world.
  local radiusCap = max(96, tonumber(qb.worldRadiusCap) or SNOW_RADIUS_MAX)
  lastFar = WP._voxelRenderDistance(streamMeta) or lastFar
  local desiredSnowR = 600
  local desiredRainR = 220
  local volumeScale=1
  if streamMeta and type(streamMeta.volume)=="table" then volumeScale=max(.72,min(1.25,tonumber(streamMeta.volume.farPrecipScale) or 1)) end
  if lastFar and lastFar > 0 then
    -- 8.1.92: snow reach is a camera/render-distance contract in BOTH front
    -- modes. The previous fronts-ON branch clamped this to 750 world units, so
    -- a host rendering farther than that exposed the edge of the snow disk and
    -- made snowfall disappear/reappear as the player crossed streaming cells.
    -- At the default 100% setting, snow now reaches the exact live voxel far
    -- distance. Lower 3D WEATHER DISTANCE values remain explicit user choices.
    desiredSnowR = max(SNOW_MIN_R, lastFar * weatherDistanceScale)
    desiredRainR = min(SNOW_RADIUS_MAX, max(96, lastFar * SNOW_FAR_FRACTION * volumeScale))
  end
  if not frontsOn and lastFar and lastFar > 0 then
    -- Fronts OFF means one uniform local weather state owns the rendered world.
    -- Rain/hail retain the same player-selected weather-only distance rule.
    desiredRainR = max(4, lastFar * weatherDistanceScale)
  end
  -- Snow coverage is a world-coverage contract, not a quality/front-radius knob.
  -- Quality may reduce particle density/count, and fronts may vary patchiness,
  -- but neither is allowed to shorten the live 3D snow volume. This guarantees
  -- that a 100% snow field cannot be out-walked before the voxel far plane.
  SNOW_STREAM_RADIUS = max(SNOW_MIN_R, desiredSnowR)
  SNOW_DRAW_RADIUS = SNOW_STREAM_RADIUS
  STREAM_RADIUS = frontsOn and min(radiusCap, desiredRainR) or max(4, desiredRainR)
  STREAM_R2 = STREAM_RADIUS * STREAM_RADIUS
  local rainCoverX,rainCoverZ=px,pz
  if not frontsOn and streamMeta and streamMeta.Voxel3D and streamMeta.Voxel3D.eye then
    rainCoverX=tonumber(streamMeta.Voxel3D.eye[1]) or rainCoverX
    rainCoverZ=tonumber(streamMeta.Voxel3D.eye[3]) or rainCoverZ
  end
  local rainSpawnX,rainSpawnZ=WP._rainCpuAnchor(rainCoverX,rainCoverZ,STREAM_RADIUS,WP._mapJustChanged)

  -- Heavy: +50%. Primal + Storm: +100% 3D rain spawn density and fall speed.
  if wxId == "HEAVY_RAIN" or wxId == "PRIMAL_RAIN" or wxId == "STORM" then
    RAIN_HEAVY_SPAWN_MUL = 2.0
    RAIN_HEAVY_FALL_MUL = 2.0
  elseif wxId == "RAIN_HEAVY" then
    RAIN_HEAVY_SPAWN_MUL = 1.5
    RAIN_HEAVY_FALL_MUL = 1.5
  else
    RAIN_HEAVY_SPAWN_MUL = 1.0
    RAIN_HEAVY_FALL_MUL = 1.0
  end

  local wantRain = 0
  if rainI > 0.02 then
    -- drops = per-tile density x rendered tiles x intensity x quality
    -- Fronts-OFF rain covers the complete rendered X/Z window, not a radial
    -- disk around the player. Use square-window area so density is preserved all
    -- the way to the voxel render edges/corners; the host far plane/frustum owns
    -- final visibility. Fronts ON keeps the inherited regional circular budget.
    local rtiles = frontsOn
      and ((math.pi * STREAM_RADIUS * STREAM_RADIUS) / (TILE * TILE))
      or (((2*STREAM_RADIUS) * (2*STREAM_RADIUS)) / (TILE * TILE))
    local rainCap = min(RAIN_MAX, max(0, floor(tonumber(qb.worldRainCap) or RAIN_MAX)))
    if weather._populationStrengthFixed then
      rainCap=max(0,floor(rainCap*weather._populationStrength+0.5))
      wantRain=min(rainCap,floor(RAIN_PER_TILE*rtiles*min(1.5,rainI/weather._populationStrength)*q*RAIN_HEAVY_SPAWN_MUL*weather._populationStrength+0.5))
    else
      wantRain=min(rainCap,floor(RAIN_PER_TILE*rtiles*min(1.5,rainI)*q*RAIN_HEAVY_SPAWN_MUL+0.5))
    end
  end

  -- SNOW VOLUME TRACKS WHAT THE HOST RENDERS.
  -- If the camera's far plane says more world is on screen, the disk grows to
  -- match and the flake count grows with its AREA -- so density per tile holds
  -- instead of the same handful of flakes being smeared over more ground. A
  -- host that publishes no far plane keeps the default radius.
  -- SANDSTORM / DUSTSTORM: widen the grain field across the rendered world
  -- so the storm surrounds the player (not a tight disk / overlay).
  if frontsOn and (wxId == "SANDSTORM" or wxId == "DUSTSTORM") then
    local stormR = max(STREAM_RADIUS * 2.45, 520)
    STREAM_RADIUS = min(radiusCap, 620, stormR)
    STREAM_R2 = STREAM_RADIUS * STREAM_RADIUS
  end
  -- ASHFALL: cover the full rendered world (same idea as dust).
  if frontsOn and (wxId == "ASHFALL" or (tonumber(weather and weather.ashIntensity) or 0) > 0.02) then
    local ashR = max(STREAM_RADIUS * 2.25, 480)
    STREAM_RADIUS = min(radiusCap, 560, ashR)
    STREAM_R2 = STREAM_RADIUS * STREAM_RADIUS
  end

  local wantSnow = 0
  if snowI > 0.02 then
    -- flakes = per-tile density x rendered tiles x intensity x quality
    local tiles = (math.pi * SNOW_STREAM_RADIUS * SNOW_STREAM_RADIUS) / (TILE * TILE)
    -- Preserve the established 1.9 visual reference, but do not clamp every
    -- stronger snow weather back to the same density. Authored Snow/Blizzard
    -- and the dedicated SNOW INTENSITY setting may scale upward until the
    -- normal quality/hard-cap ceilings stop them.
    local want = SNOW_PER_TILE * tiles * min(5.0, (weather._populationStrengthFixed and (snowI/weather._populationStrength) or snowI) / 1.9) * q
    -- BLIZZARD only: +100% 3D snow spawn
    local snowCap = min(SNOW_MAX, max(0, floor(tonumber(qb.worldSnowCap) or SNOW_MAX)))
    if wxId == "BLIZZARD" then
      want = want * 2.0
      snowCap = max(0, floor(tonumber(qb.worldBlizzardCap) or (SNOW_MAX * 2)))
    end
    if weather._populationStrengthFixed then
      want=want*weather._populationStrength
      snowCap=max(0,floor(snowCap*weather._populationStrength+0.5))
    end
    -- 8.2.5 requested visible-density multipliers. Apply them AFTER the
    -- established 8.2.4 weather/quality cap calculation so each named weather
    -- is an exact multiplier of its previous logical 3D snow population while
    -- leaving every other snow weather and every CPU fallback budget unchanged.
    local previousWantSnow = min(snowCap, floor(want + 0.5))
    local visibleMul = 1
    if wxId == "SNOW_LIGHT" or wxId == "SNOW" or wxId == "THUNDERSNOW" or wxId == "TSNOW" or wxId == "DRAGONSTORM" then
      visibleMul = 2
    elseif wxId == "BLIZZARD" then
      visibleMul = 4
    end
    wantSnow = previousWantSnow * visibleMul
  end

  -- 8.1.54: once the real procedural backend has completed an in-host draw
  -- probe, it owns the ENTIRE visible snow population, including the near
  -- field. Lua retains only a tiny interaction sample for first-person face
  -- specks. Ground collision/settling is intentionally disabled in 8.1.54
  -- while the SnowPack surface resolver is being repaired. This preserves the
  -- exact logical 100k/200k visual population without per-flake CPU integration
  -- or near-field instance uploads on supported hosts.
  -- 8.2.4 full-path performance authority.
  --
  -- There are TWO fundamentally different snow costs:
  --   1) a proven procedural GPU field, where Lua needs only a tiny face-contact
  --      sample; and
  --   2) the compatibility CPU renderer, where every simulated flake is also
  --      integrated and rebuilt into a dynamic visible mesh every frame.
  --
  -- 8.2.3 still initialized wantSnowSim to the complete logical storm. If a
  -- phone rejected the procedural shader/point path, the fallback therefore
  -- became 2,400 CPU flakes even on POTATO and up to 200,000 on MAX BLIZZARD.
  -- That is catastrophic and also bypasses the long-standing per-quality
  -- `qb.snow` CPU budget. The fallback now obeys that CPU budget immediately,
  -- including the first frame before a procedural draw has been proven.
  local cpuSnowCap=max(24,floor(tonumber(qb.snow) or 720))
  local wantSnowSim=min(wantSnow,cpuSnowCap)
  local gpuSnow=0
  local snowFullGPU=false
  local simRadius=SNOW_STREAM_RADIUS
  local function faceProbeTarget()
    -- Third-person needs one telemetry/lifecycle identity only. First-person
    -- keeps a tiny bounded face-contact sample; aggregate SnowPack deposition
    -- owns ground coverage, so 96 exact-support flakes are unnecessary.
    local face=(lastEye~=nil) and firstPerson()
    if not face then return min(wantSnow,1) end
    local qcap=max(4,floor((tonumber(qb.snowProbeCap) or 96)/6+0.5))
    return min(wantSnow,min(16,qcap))
  end
  if wantSnow>0 then
    local PS=WP._proceduralSnowModule()
    local gpuOK=false
    if PS and PS.canVirtualize then local ok,v=V.safeCall(PS.canVirtualize);gpuOK=ok and v==true end
    if gpuOK then
      snowFullGPU=true
      simRadius=min(SNOW_STREAM_RADIUS,48)
      wantSnowSim=faceProbeTarget()
      gpuSnow=wantSnow
    end
  end

  -- 8.1.54: once ProceduralPrecipField is driver-proven, it owns the complete
  -- visible rain field. The CPU keeps only 96 interaction probes for lens hits,
  -- roof/canopy interception and wet/splash events. Unsupported hosts retain
  -- the complete legacy CPU simulation/draw path.
  -- Capture the 0 -> raining edge before rain.active is overwritten below.
  -- On that one frame every physical slot is refreshed and stratified through
  -- the fall column, including stale pooled slots left from an earlier storm.
  local primeRain = wantRain > 0 and (rain.active or 0) <= 0
  if wantRain > 0 and WP._mapJustChanged then primeRain=true end
  -- 8.2.6 all-weather performance qualification: visible rain must never route
  -- a world-scale logical population through the legacy CPU recycler. Start from
  -- the quality-tier CPU safety cap, then hand the complete authored population
  -- to the procedural GPU backend whenever that backend has been proven. This
  -- applies at EVERY nonzero density; the old fronts/1200 threshold made low-tier
  -- rain paradoxically more CPU-heavy than dense rain on phones.
  local cpuRainCap=max(24,floor(tonumber(qb.rain) or 720))
  rain.simActive=min(wantRain,cpuRainCap);rain.gpuActive=0;rain.gpuFullVisual=false;rain.simRadius=STREAM_RADIUS
  if wantRain>0 then
    local PP=WP._proceduralPrecipModule();local gpuOK=false
    if PP and PP.canVirtualize then local ok,v=V.safeCall(PP.canVirtualize);gpuOK=ok and v==true end
    if gpuOK then
      rain.gpuFullVisual=true
      rain.simRadius=min(STREAM_RADIUS,48)
      rain.simActive=min(wantRain,96)
      rain.gpuActive=wantRain
    end
  end
  do local recycleMul=(WP._uniformPrecipField==true) and 1.55 or 1.25;rain.recycleR2=(rain.simRadius*recycleMul)*(rain.simRadius*recycleMul) end
  rain.lastIntensity,rain.lastWindX,rain.lastWindZ=rainI,windX,windZ

  -- 8.1.64: the corrected bounded SnowPack support resolver is live again.
  -- Build one shared support context for rain interception, snow settling,
  -- persistent banks and footprints. This does NOT restore the retired full
  -- CPU snow population: on procedural hosts only the <=96 interaction probes
  -- below touch SnowPack, while the GPU field still owns the visual storm.
  local groundY = groundMarkY - 0.3
  -- 8.1.76: the procedural rain fall column must not use the player's current
  -- Y as its lower phase boundary. Hopping a 6-unit ledge changed totalH for
  -- every procedural drop at once, causing a visible rain pause/rephase even
  -- though X/Z ownership was world-fixed. Freeze a padded world bottom for the
  -- whole rain episode/map. Small player elevation changes therefore cannot
  -- rephase the storm; a real map change or a fresh rain start establishes a
  -- new column. The 32-unit pad comfortably covers authored flat-world ledges.
  if wantRain>0 and (primeRain or WP._mapJustChanged or rain.fieldBottomY==nil) then
    rain.fieldBottomY=groundY-32
  elseif wantRain<=0 then
    rain.fieldBottomY=nil
  end
  local SP=snowPackModule()
  -- 8.1.69: SNOW ACCUMULATION is independent from falling-snow intensity.
  -- Keep SnowPack's exact support resolver live even while accumulation is OFF
  -- so bounded CPU snow probes still collide/recycle at the real terrain floor.
  local accumulationOn=true
  local S=settingsModule()
  if S and S.snowAccumulationEnabled then
    local ok,v=V.safeCall(S.snowAccumulationEnabled)
    if ok then accumulationOn=(v~=false) end
  end
  if SP and SP.setEnabled then V.safeCall(SP.setEnabled,accumulationOn) end
  if not accumulationOn then
    WP._snowPackDepositAcc=0
    WP._snowPackStormAge=0
  end
  local snowCtx=nil
  -- 8.2.4: SNOW ACCUMULATION OFF must really turn the SnowPack/support hot path
  -- off for pure snowfall. 8.2.3 still rebuilt the full support context every
  -- frame and ran exact surface sweeps for invisible snow probes even though no
  -- bank could be deposited. Rain still needs the shared support context for
  -- roof/canopy/material impacts.
  local supportCtxNeeded=(accumulationOn and wantSnow>0) or rainI>0.02
  if supportCtxNeeded and SP and SP.ACCUMULATION_ENABLED and SP.beginFrame then
    local refreshCtx=true
    if accumulationOn and wantSnow>0 and rainI<=0.02 then
      -- Pure snow accumulation is a slow ground process. Reuse the exact support
      -- context for 100 ms; map changes or meaningful movement refresh it
      -- immediately. This removes 5/6 of the region/ground-cache setup work at
      -- 60 FPS without lowering falling-snow animation cadence.
      local cx,cz=tonumber(WP._snowSupportX),tonumber(WP._snowSupportZ)
      local dx,dz=cx and (px-cx) or 1e9,cz and (pz-cz) or 1e9
      refreshCtx=(WP._snowSupportCtx==nil) or WP._mapJustChanged==true
        or (simTime-(tonumber(WP._snowSupportAt) or -1e9)>=0.10)
        or (dx*dx+dz*dz>=144)
      if not refreshCtx then snowCtx=WP._snowSupportCtx end
    end
    if refreshCtx then
      local ok,ctx=V.safeCall(SP.beginFrame,streamMeta,groundY,hostVoxelSceneModule(),hostTileShapeModule(),WP._hostStructuresModule())
      if ok then
        snowCtx=ctx
        if accumulationOn and wantSnow>0 and rainI<=0.02 then
          WP._snowSupportCtx,WP._snowSupportAt,WP._snowSupportX,WP._snowSupportZ=ctx,simTime,px,pz
        end
      end
    end
  else
    WP._snowSupportCtx,WP._snowSupportAt,WP._snowSupportX,WP._snowSupportZ=nil,nil,nil,nil
  end

  -- WorldInteractionPrecip owns rain roof/canopy beads, not snowfall. Do not
  -- run its fixed 128-slot update loop on every pure-snow frame just because the
  -- module exists; only advance it while rain is active or retained beads are
  -- still alive from a preceding rain frame.
  if WorldInteractionPrecip and WorldInteractionPrecip.update then
    local interactionLive=false
    if WorldInteractionPrecip.stats then
      local ok,st=V.safeCall(WorldInteractionPrecip.stats)
      interactionLive=ok and st and (tonumber(st.active) or 0)>0
    end
    if rainI>0.02 or interactionLive then WorldInteractionPrecip.update(rainDt,snowCtx,SP,px,pz,addWetMark) end
  end

  ensureRain(rain.simActive)
  ensureSnow(wantSnowSim)
  if rain.gpuFullVisual and rain.n>max(rain.simActive*2,rain.simActive+256) then WP._trimPool(rain,rain.simActive,"rain") end
  if snowFullGPU and snow.n>max(wantSnowSim*2,wantSnowSim+256) then WP._trimPool(snow,wantSnowSim,"snow") end
  -- Weather off / CLEAR: drop live particle counts immediately so 3D precip
  -- does not keep drawing the previous storm for a few frames.
  if wantRain <= 0 then rain.active,rain.simActive,rain.gpuActive,rain.gpuFullVisual=0,0,0,false end
  if wantSnow <= 0 then snow.active,snow.simActive,snow.gpuActive,snow.gpuFullVisual=0,0,0,false end

  -- ---- RAIN (world-space integration + flat-world structure interception) --
  local rx, ry, rz = rain.x, rain.y, rain.z
  local rvx, rvy, rvz, rhs = rain.vx, rain.vy, rain.vz, rain.hSpeed
  local rlife, rmax, rseed, rgrav = rain.life, rain.maxLife, rain.seed, rain.grav
  local rEye = lastEye
  local fpvNow = (rEye ~= nil) and firstPerson()
  local rainWantFace = fpvNow
  local splashEnabled = splashesEnabled() and (qb.splash == nil or (tonumber(qb.splash) or 0) > 0)
  local rex, rey, rez = 0, 0, 0
  if rainWantFace then rex, rey, rez = rEye[1] or 0, rEye[2] or 0, rEye[3] or 0 end
  local rainSteerAmt = windMag > 0.01 and math.min(1, rainDt * 0.75) or 0
  for i = 1, rain.simActive do
    if primeRain then
      spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, true)
    elseif rx[i] == 0 and ry[i] == 0 and rz[i] == 0 and rlife[i] == 0 then
      spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)
    end
    rlife[i] = rlife[i] + rainDt
    -- Live gusts gently steer already-falling drops. Newly spawned drops still
    -- get personal velocity variance, while long-lived drops curve naturally
    -- into a changing world wind instead of keeping an obsolete heading.
    if rainSteerAmt > 0 then
      rvx[i], rvz[i] = steerHorizontalCached(rvx[i], rvz[i], windDirX, windDirZ, rhs[i], rainSteerAmt)
    end
    -- Integrate independent velocity (world axes only)
    rx[i] = rx[i] + rvx[i] * rainDt
    ry[i] = ry[i] + rvy[i] * rainDt
    rz[i] = rz[i] + rvz[i] * rainDt
    -- Mild gravity reinforcement (per-drop variation already in vy)
    rvy[i] = rvy[i] - (rgrav[i] or (18 + (rseed[i] or 0) * 8)) * rainDt
    -- Was `py - 2`, a fixed couple of units, while snow settles at
    -- py - GROUND_DROP (a full tile lower). Rain stopping a tile above where
    -- snow lands is the same "falls short of the floor" bug, so both now use
    -- the one ground plane.
    -- Rain on the lens. Snow had face contact from 4.28.69 and rain had none,
    -- which is backwards: a drop hitting you is a far stronger first-person cue
    -- than a flake, because it arrives fast and bursts. Same mechanism -- the
    -- speck exists only because a simulated drop really intersected the eye
    -- sphere -- so it is a consequence of the sim, not a screen overlay.
    --
    -- Written with a flag rather than `goto`: goto is Lua 5.2+, and while
    -- LuaJIT accepts it, plain 5.1 does not. This module has already been dead
    -- on arrival once over a dialect mistake (5.3 bitwise operators) and is not
    -- going there twice.
    local rHit = false
    if rainWantFace then
      local fx, fy, fz = rx[i] - rex, ry[i] - rey, rz[i] - rez
      if (fx * fx + fy * fy + fz * fz) < FACE_R2 then
        addFaceHit(fx, fy, fz, rain.size[i] * 1.6)
        spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)
        rHit = true
      end
    end
    if rHit then
      -- consumed on the lens
    else
      -- Flat-world structure/material interception. The same exact support
      -- resolver used by snow now classifies liquid impacts so grass, water, ice,
      -- canopy and hard raised surfaces do not all produce the same splash.
      local structureHit=false
      local surfaceY,kind,class,art,profile=nil,nil,nil,nil,nil
      if snowCtx and snowCtx.collisionEnabled and SP and SP.surfaceAt
          and ry[i] < groundMarkY + 96 then
        surfaceY,kind,class,art,profile=SP.surfaceAt(snowCtx,rx[i],rz[i])
        local sy=tonumber(surfaceY) or groundMarkY
        local raised=(kind=="raised");local canopy=(kind=="tree")
        local surfaceContact=(raised or canopy or kind=="water" or kind=="ice" or kind=="grass") and ry[i] <= sy+0.35
        if surfaceContact then
          local canopyPass=canopy and (((tonumber(rseed[i]) or 0)*997.0)%1.0)>0.58
          if canopyPass then
            -- A permeable canopy pass must continue toward the real ground. Do
            -- not let the generic ground branch immediately reinterpret the
            -- crown height as the landing plane.
            surfaceY,kind,class,art,profile=nil,nil,nil,nil,nil
          end
          if not canopyPass then
            rainLanded=rainLanded+1
            if raised then
              if WorldInteractionPrecip and WorldInteractionPrecip.spawnRoof then WorldInteractionPrecip.spawnRoof(snowCtx,SP,rx[i],sy,rz[i],rseed[i],false) end
            elseif canopy then
              if WorldInteractionPrecip and WorldInteractionPrecip.spawnCanopy then WorldInteractionPrecip.spawnCanopy(snowCtx,rx[i],sy,rz[i],false) end
            elseif splashEnabled then
              addWetMark(rx[i],sy,rz[i],0.30+random()*0.42,kind,class,art)
            end
            spawnRainAt(i,rainSpawnX,py,rainSpawnZ,rainI,windX,windZ,rain.simRadius,false)
            structureHit=true
          end
        end
      end
      if structureHit then
        -- consumed on roof/prop/canopy/material surface
      else
        local impactY=tonumber(surfaceY) or groundMarkY
        if ry[i] < impactY then
          rainLanded = rainLanded + 1
          if splashEnabled then
            addWetMark(rx[i], impactY, rz[i], 0.35 + random() * 0.45, kind, class, art)
          end
          spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)
      elseif rlife[i] >= rmax[i] or ((rx[i]-rainSpawnX)*(rx[i]-rainSpawnX)+(rz[i]-rainSpawnZ)*(rz[i]-rainSpawnZ)) > (rain.recycleR2 or STREAM_R2) then
        spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)
      end
      end
    end
  end
  rain.active = wantRain

  -- Age wet marks (dry-up).
  local wActive = wet.active or 0
  local wage = wet.age
  for i = 1, wActive do
    local life=wet.life[i] or WET_LIFE
    if wage[i] < life then wage[i] = wage[i] + dt end
  end

  -- Random small wet flecks across the whole rain volume (not only under the player).
  if rainI > 0.05 and splashEnabled then
    local rate = 28 * min(1.6, rainI) * rainDt
    local nSpawn = floor(rate)
    if random() < (rate - nSpawn) then nSpawn = nSpawn + 1 end
    for _ = 1, nSpawn do
      local ang = random() * PI2
      local rad = (random() ^ 0.4) * STREAM_RADIUS
      -- Same plane as landing drops (depositGroundY), not head height.
      addWetMark(rainSpawnX + cos(ang) * rad, groundMarkY, rainSpawnZ + sin(ang) * rad, 0.22 + random() * 0.38)
    end
  end

  -- ---- SNOW ----------------------------------------------------------------
  local sx, sy, sz = snow.x, snow.y, snow.z
  local svx, svy, svz, shs = snow.vx, snow.vy, snow.vz, snow.hSpeed
  local slife, smax, sseed = snow.life, snow.maxLife, snow.seed
  local sph, srot, sspin = snow.ph, snow.rot, snow.spin
  -- `groundY` remains the lifecycle floor. SnowPack is intentionally absent
  -- from the falling-snow integration path in 8.1.54.
  local recycleR2 = (simRadius * 1.25) * (simRadius * 1.25)
  -- Face contact only in true first person. Third-person / tilted 3D must not
  -- leave camera-locked "ceiling" snow splashes.
  local eye = lastEye
  local wantFace = (eye ~= nil) and fpvNow
  local ex, ey, ez = 0, 0, 0
  if wantFace then ex, ey, ez = eye[1] or 0, eye[2] or 0, eye[3] or 0 end

  local snowSteerAmt = windMag > 0.01 and math.min(1, dt * 0.48) or 0
  for i = 1, wantSnowSim do
    if WP._mapJustChanged or (slife[i] <= 0 and smax[i] <= 0)
        or (sx[i] == 0 and sy[i] == 0 and sz[i] == 0 and slife[i] == 0) then
      spawnSnowAt(i, px, py, pz, snowI, windX, windZ, true, simRadius)
    end
    slife[i] = slife[i] + dt
    local seed = sseed[i] or 0.5
    local ph = (sph[i] or 0) + dt * (0.7 + seed * 1.4)
    sph[i] = ph
    srot[i] = (srot[i] or 0) + (sspin[i] or 0) * dt
    if snowSteerAmt > 0 then
      svx[i], svz[i] = steerHorizontalCached(svx[i], svz[i], windDirX, windDirZ, shs[i], snowSteerAmt)
    end
    local oldSX,oldSY,oldSZ=sx[i],sy[i],sz[i]

    -- Same motion equations, deriving invariant coefficients from the already
    -- stored seed. Seven redundant 200k-entry arrays used to hold these exact
    -- affine expressions and increased both RAM footprint and cache misses.
    local turb = 1.1 + seed * 2.4
    local swayX = fsin(ph) * turb + fsin(ph * 0.41 + seed * 5.2) * turb * 0.75
    local swayZ = fcos(ph * 0.88 + seed) * turb * 0.95 + fcos(ph * 0.33 + seed * 3.7) * turb * 0.55
    local bob = fsin(ph * 1.15 + seed * 2.8) * (0.55 + seed * 0.7)
    sx[i] = sx[i] + (svx[i] + swayX) * dt
    sy[i] = sy[i] + (svy[i] + bob) * dt
    sz[i] = sz[i] + (svz[i] + swayZ) * dt

    -- Soft gravity toward a lower terminal speed (matches the 40% slower fall).
    if svy[i] > -14 then
      svy[i] = svy[i] - (0.7 + seed * 1.2) * dt
    end

    -- NO player wrap. Flakes keep world positions. Only recycle when:
    --   hit the eye, hit ground, lifetime ends, or drifted out of the volume.
    local recycle = false

    if wantFace then
      local fx, fy, fz = sx[i] - ex, sy[i] - ey, sz[i] - ez
      if (fx * fx + fy * fy + fz * fz) < FACE_R2 then
        -- A real flake really reached the eye. Consume it and leave a speck.
        addFaceHit(fx, fy, fz, snow.size[i])
        recycle = true
      end
    end

    if not recycle then
      local dx = sx[i] - px
      local dz = sz[i] - pz
      local depth = py - sy[i]
      if depth > snowDeepest then snowDeepest = depth end
      -- 8.1.64: resolve only the bounded interaction probes against exact
      -- point support. A hit deposits SnowPack state and recycles the probe;
      -- the procedural/GPU field remains the visual owner of dense snowfall.
      -- The procedural visual field does not need per-probe terrain sweeps.
      -- Aggregate SnowPack deposition handles accumulated ground coverage, and
      -- the tiny CPU sample exists only for face contact/telemetry. Keep exact
      -- flake-vs-terrain resolution solely for the capped legacy CPU-visible
      -- fallback, where those simulated flakes are the actual visible field.
      if (not snowFullGPU) and i<=max(8,floor(tonumber(qb.snowProbeCap) or 96))
          and snowCtx and snowCtx.collisionEnabled and SP and SP.resolveFlake then
        local hit=SP.resolveFlake(snowCtx,oldSX,oldSY,oldSZ,sx[i],sy[i],sz[i],snow.size[i])
        if hit then snowLanded=snowLanded+1; recycle=true end
      end
      if not recycle and sy[i] < groundY - 8 then
        recycle = true
      elseif not recycle and slife[i] >= (smax[i] or 8) then
        snowExpiredAir = snowExpiredAir + 1
        recycle = true
      elseif (dx * dx + dz * dz) > recycleR2 then
        recycle = true
      end
    end

    if recycle then
      spawnSnowAt(i, px, py, pz, snowI, windX, windZ, false, simRadius)
    end
  end
  snow.active,snow.simActive,snow.gpuActive,snow.simRadius,snow.gpuFullVisual=wantSnow,wantSnowSim,gpuSnow,simRadius,snowFullGPU
  snow.lastIntensity,snow.lastWindX,snow.lastWindZ=snowI,windX,windZ

  -- 8.1.64: advance persistent SnowPack state for snow, post-snow melting and
  -- player tracks, then stage only the quality-bounded visible prefixes.
  if accumulationOn and SP and SP.update then V.safeCall(SP.update,dt,snowCtx,wantSnow>0,wxId) end
  if accumulationOn and snowCtx and snowCtx.collisionEnabled and SP and SP.fillGroundPool and SP.fillFootPool then
    -- Dense procedural snow has only <=96 CPU interaction probes, so literal
    -- probe impacts alone would leave a visually empty ground field. Convert
    -- the logical GPU snowfall into a tiny bounded aggregate deposition stream.
    -- The inherited safety ceiling remains at most 24 exact-support samples/second;
    -- 8.1.68 deliberately runs lower, topping out at 18 after its startup ramp.
    -- 8.1.68 removes the old 4px 9x9 player lattice entirely: that deterministic
    -- grid was visible as straight accumulation lines and repeatedly hammered
    -- the same nearby points at storm startup. A golden-angle field distributes
    -- support samples over the full local snowfall footprint instead.
    if accumulationOn and wantSnow>0 and SP.deposit then
      WP._snowPackStormAge=min(180,(tonumber(WP._snowPackStormAge) or 0)+dt)
      local ramp=min(1,WP._snowPackStormAge/45)
      local sampleRate=min(18,max(2.0,snowI*3.6))*(0.16+0.84*ramp)
      WP._snowPackDepositAcc=(tonumber(WP._snowPackDepositAcc) or 0)+dt*sampleRate
      local dn=floor(WP._snowPackDepositAcc)
      WP._snowPackDepositAcc=WP._snowPackDepositAcc-dn
      for j=1,dn do
        WP._snowPackDepositSerial=(tonumber(WP._snowPackDepositSerial) or 0)+1
        local serial=WP._snowPackDepositSerial
        local u=fhash(serial,0.173+simTime*0.011)
        local v=fhash(serial,0.619+simTime*0.017)
        local a=serial*2.399963229728653+(u-0.5)*0.48
        -- Accumulation covers the same effective field as visible 3D snow.
        -- 8.1.72 made precipitation distance player-adjustable, but the bank
        -- sampler was still hard-coded to 112 units and therefore formed a
        -- small white circle around the player. Sample the full live snow field.
        local radius=4+sqrt(v)*max(0,SNOW_STREAM_RADIUS-4)
        local dx,dz=cos(a)*radius,sin(a)*radius
        local snowPX,snowPZ=px,pz
        local liveP=streamMeta and streamMeta.player
        if liveP and tonumber(liveP.px) and tonumber(liveP.py) then
          -- Anchor the broad distributed field to the gameplay player's actual
          -- sprite centre, not a camera/voxel focus with a different origin.
          snowPX,snowPZ=tonumber(liveP.px)+8,tonumber(liveP.py)+8
        end
        local depositFn=SP.depositAggregate or SP.deposit
        depositFn(snowCtx,snowPX+dx,snowPZ+dz,0.72+0.48*fhash(serial,0.911))
      end
    else
      WP._snowPackDepositAcc=0
      WP._snowPackStormAge=0
    end
    ensureGSnow()
    -- 8.2.3: accumulated banks are a slow-changing physical field, not a
    -- falling-particle animation. The old path rescanned up to 2048 SnowPack
    -- cells, restaged up to thousands of patches, rerasterized coverage, and
    -- rebuilt/uploaded the complete bank mesh on EVERY frame. Refresh the
    -- staged world bank at 10 Hz (or immediately after meaningful movement/map
    -- change), then reuse the exact immutable staged geometry between refreshes.
    -- Falling snow remains full per-render-frame animation; this cadence applies
    -- only to ground accumulation whose depth evolves far more slowly.
    local gx,gz=tonumber(WP._gsnowStageX),tonumber(WP._gsnowStageZ)
    local gdx,gdz=gx and (px-gx) or 1e9,gz and (pz-gz) or 1e9
    local stageDue=(WP._mapJustChanged==true) or (WP._gsnowStageAt==nil)
      or (simTime-(tonumber(WP._gsnowStageAt) or -1e9)>=0.10)
      or (gdx*gdx+gdz*gdz>=144)
    if stageDue then
      V.safeCall(SP.fillGroundPool,gsnow,max(0,floor(tonumber(qb.snowPackDrawCap) or GSNOW_MAX)),snowCtx,px,pz,SNOW_STREAM_RADIUS)
      V.safeCall(SP.fillFootPool,foot,max(0,floor(tonumber(qb.footDrawCap) or FOOT_MAX)),snowCtx)
      WP._gsnowStageAt,WP._gsnowStageX,WP._gsnowStageZ=simTime,px,pz
      WP._gsnowPoolRevision=(tonumber(WP._gsnowPoolRevision) or 0)+1
      local SSP=WP._snowSurfacePaintModule()
      if SSP and SSP.capture then V.safeCall(SSP.capture,snowCtx,gsnow,px,pz,SNOW_STREAM_RADIUS) end
    end
  else
    gsnow.active=0; foot.active=0
    WP._gsnowStageAt,WP._gsnowStageX,WP._gsnowStageZ=nil,nil,nil
    WP._gsnowPoolRevision=(tonumber(WP._gsnowPoolRevision) or 0)+1
    local SSP=WP._snowSurfacePaintModule()
    if SSP and SSP.clearCapture then V.safeCall(SSP.clearCapture) end
  end

  -- Age face specks.
  local fActive = face.active or 0
  for i = 1, fActive do
    if face.age[i] < FACE_LIFE then face.age[i] = face.age[i] + dt end
  end

  -- ---- GRAINS: hail / sand / ash / debris-leaves ---------------------------
  -- A weather may legitimately request MORE THAN ONE grain family. Sandstorm
  -- carries blowing debris, and DRAGONSTORM carries sand + debris at the same
  -- time. The old implementation picked exactly one family by priority, so a
  -- valid sand channel silently stole the only grain slot and 3D leaves never
  -- spawned. Keep one allocation pool, but partition its active prefix into a
  -- segment per family so every requested animation can coexist.
  local wxGrain = tostring((weather and weather.wxId) or wxId or ""):upper()
  -- ASHFALL historically had an explicit floor; retain it without zeroing any
  -- other family. CinematicAtmos now hard-resets and re-derives every driver on
  -- every frame, so stale channels no longer need an exclusive-family hack.
  if wxGrain == "ASHFALL" and ashI < 0.02 then ashI = 1.45 end

  local grainWant = grain.target
  local grainDistanceAreaScale = (not frontsOn) and (weatherDistanceScale * weatherDistanceScale) or 1.0
  grainWant[1], grainWant[2], grainWant[3], grainWant[4] = 0, 0, 0, 0
  if hailI > 0.02 then
    local hailCap=min(HAIL_MAX,max(0,floor(tonumber(qb.worldHailCap) or HAIL_MAX)))
    if weather._populationStrengthFixed then hailCap=max(0,floor(hailCap*weather._populationStrength+0.5)) end
    grainWant[1] = min(hailCap, floor(HAIL_MAX * min(1.6, weather._populationStrengthFixed and (hailI/weather._populationStrength) or hailI) * 0.8 * q * grainDistanceAreaScale * (weather._populationStrengthFixed and weather._populationStrength or 1) + 0.5))
  end
  if sandI > 0.02 then
    local sandMax = min(GRAIN_MAX * 12,max(0,floor(tonumber(qb.worldSandCap) or (GRAIN_MAX*12))))
    if weather._populationStrengthFixed then sandMax=max(0,floor(sandMax*weather._populationStrength+0.5)) end
    grainWant[2] = min(sandMax, floor(GRAIN_MAX * min(2.4, weather._populationStrengthFixed and (sandI/weather._populationStrength) or sandI) * 0.85 * q * 12 * grainDistanceAreaScale * (weather._populationStrengthFixed and weather._populationStrength or 1) + 0.5))
  end
  if debrisI > 0.02 then
    local debrisCap=min(GRAIN_MAX,max(0,floor(tonumber(qb.worldDebrisCap) or GRAIN_MAX)))
    if weather._populationStrengthFixed then debrisCap=max(0,floor(debrisCap*weather._populationStrength+0.5)) end
    grainWant[3] = min(debrisCap, floor(GRAIN_MAX * min(1.8, weather._populationStrengthFixed and (debrisI/weather._populationStrength) or debrisI) * 0.85 * q * grainDistanceAreaScale * (weather._populationStrengthFixed and weather._populationStrength or 1) + 0.5))
  end
  if ashI > 0.02 then
    -- Dense ash from the cloud bank (grey + black). Spawn count ×3.
    local ashMax = min(GRAIN_MAX * 3,max(0,floor(tonumber(qb.worldAshCap) or (GRAIN_MAX*3))))
    if weather._populationStrengthFixed then ashMax=max(0,floor(ashMax*weather._populationStrength+0.5)) end
    grainWant[4] = min(ashMax, floor(GRAIN_MAX * min(2.0, weather._populationStrengthFixed and (ashI/weather._populationStrength) or ashI) * 0.90 * q * 3 * grainDistanceAreaScale * (weather._populationStrengthFixed and weather._populationStrength or 1) + 0.5))
  end

  grain.intensity[1],grain.intensity[2],grain.intensity[3],grain.intensity[4]=hailI,sandI,debrisI,ashI
  grain.lastWindX,grain.lastWindZ=windX,windZ
  grain.proceduralOK=false;grain.procedural=WP._proceduralPrecipModule()
  if grain.procedural and grain.procedural.supported then local ok,v=V.safeCall(grain.procedural.supported);grain.proceduralOK=ok and v==true end
  local cpuGrainCap=max(12,floor(tonumber(qb.grain) or 260))
  for kind=1,4 do
    local logical=grainWant[kind] or 0
    -- Leaves/debris stay fully physical because settling/NPC/building collision
    -- is authored behavior. Noninteractive hail/sand/ash default to a bounded
    -- CPU compatibility population, never the world logical population.
    grain.simTarget[kind]=(kind==3) and logical or min(logical,cpuGrainCap)
    grain.gpuTarget[kind]=0;grain.gpuFullVisual[kind]=false
    grain.simRadius[kind]=(kind==3) and STREAM_RADIUS or desiredRainR
    -- Simulation/interactions may collapse to a tiny probe radius after GPU
    -- virtualization, but visible weather never may. Hail/sand/ash keep the
    -- full live voxel render-distance contract when fronts are OFF.
    grain.visualRadius[kind]=(kind==3) and STREAM_RADIUS or desiredRainR
    -- 8.2.6: if the procedural backend is proven, it owns every nonzero visual
    -- hail/sand/ash population, including POTATO/LOW counts below the old 1200
    -- threshold. This removes the low-tier CPU inversion while preserving all
    -- logical GPU counts and keeping leaves physical.
    if kind~=3 and logical>0 and grain.proceduralOK then
      local can=false
      if grain.procedural.canVirtualize then local ok,v=V.safeCall(grain.procedural.canVirtualize);can=ok and v==true end
      if can then
        grain.gpuFullVisual[kind]=true
        grain.simRadius[kind]=4
        grain.simTarget[kind]=0
        grain.gpuTarget[kind]=logical
      end
    end
  end
  local wantGrain = grain.simTarget[1] + grain.simTarget[2] + grain.simTarget[3] + grain.simTarget[4]
  ensureGrain(wantGrain)
  -- Once any noninteractive grain family has real GPU ownership, release the
  -- retired CPU visual pool immediately instead of retaining its old high-water
  -- mark. This is transition-only work because pool.n==wantGrain afterward.
  local grainHasGPUVisual = grain.gpuFullVisual[1] or grain.gpuFullVisual[2] or grain.gpuFullVisual[4]
  if grain.n>wantGrain and (grainHasGPUVisual or grain.n>max(wantGrain*2,wantGrain+512)) then
    WP._trimPool(grain,wantGrain,"grain")
  end
  local gx, gy, gz = grain.x, grain.y, grain.z
  local gvx, gvy, gvz = grain.vx, grain.vy, grain.vz
  local LP = leafPhysicsModule()
  local leafCtx = nil
  if LP and LP.beginFrame and (grain.simTarget[3] or 0) > 0 then
    local ok, ctx = V.safeCall(LP.beginFrame, streamMeta, groundY, hostVoxelSceneModule())
    if ok then leafCtx = ctx end
  end
  local leafSettleCap = floor((grain.simTarget[3] or 0) * ((LP and LP.MAX_SETTLED_FRACTION) or 0.28) + 0.5)
  local leafSettled = 0
  if (grain.simTarget[3] or 0) > 0 then
    local leafFirst = (grain.simTarget[1] or 0) + (grain.simTarget[2] or 0) + 1
    local leafLast = leafFirst + (grain.simTarget[3] or 0) - 1
    for li = leafFirst, leafLast do
      if grain.kind[li] == 3 and grain.leafSettled[li] then leafSettled = leafSettled + 1 end
    end
  end
  local slot = 0
  for grainKind = 1, 4 do
    local familyCount = grain.simTarget[grainKind] or 0
    grain.start[grainKind] = slot + 1
    local steerRate = (grainKind == 2 and 1.10) or (grainKind == 3 and 1.35) or (grainKind == 4 and 0.42) or 0.30
    local grainSteerAmt = windMag > 0.01 and math.min(1, dt * steerRate) or 0
    for _ = 1, familyCount do
      slot = slot + 1
      local i = slot
      -- Fresh slots start at origin with maxLife=1 — force a real spawn. A
      -- weather transition may also repurpose this slot for another family.
      if WP._mapJustChanged or (gx[i] == 0 and gy[i] == 0 and gz[i] == 0 and grain.life[i] == 0)
          or grain.kind[i] ~= grainKind then
        spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, true, grain.simRadius[grainKind])
      end
      grain.life[i] = grain.life[i] + dt
      if grainSteerAmt > 0 then
        gvx[i], gvz[i] = steerHorizontalCached(gvx[i], gvz[i], windDirX, windDirZ, grain.hSpeed[i], grainSteerAmt)
      end
      -- Sand turbulence: small eddy noise so grit does not lock into parallel lines
      if grainKind == 2 then
        local seed=grain.seed[i] or .5
        local wob = fsin(simTime * (3.2 + seed * 6.5) + seed * 14.0) * 8.5
        local wob2 = fcos(simTime * (2.4 + seed * 4.0) + seed * 9.0) * 6.0
        gx[i] = gx[i] + (gvx[i] + wob) * dt
        gy[i] = gy[i] + (gvy[i] + wob2 * 0.35) * dt
        gz[i] = gz[i] + (gvz[i] + wob2) * dt
      elseif grainKind == 3 then
        -- Leaf flutter plus real voxel/NPC contact. Leaves remain ordinary
        -- world particles while airborne; collision only changes their world
        -- trajectory/state and never parents them to a camera or actor.
        -- Repair initial/legacy penetration before integrating. A swept test
        -- assumes its starting point is free; without this guard a leaf born
        -- inside a building could legitimately see only decreasing heights and
        -- escape through the outer wall. Retry several normal spawns, then lift
        -- above the sampled solid surface as a fail-safe.
        if LP and leafCtx and LP.isPenetrating and not grain.leafSettled[i] then
          local penetrating, top = LP.isPenetrating(leafCtx, gx[i], gy[i], gz[i])
          local tries = 0
          while penetrating and tries < 5 do
            spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, false, grain.simRadius[grainKind])
            tries = tries + 1
            penetrating, top = LP.isPenetrating(leafCtx, gx[i], gy[i], gz[i])
          end
          if penetrating then
            gy[i] = max(gy[i], (tonumber(top) or groundY) + (LP.LEAF_RADIUS or 1.25) + 0.35)
          end
        end
        local oldX, oldY, oldZ = gx[i], gy[i], gz[i]
        if not grain.leafSettled[i] then
          local seed=grain.seed[i] or .5
          local flutter = fsin(simTime * (3.6 + seed * 5.0) + seed * 11.0) * 7.0
          local bob = fcos(simTime * (2.2 + seed * 3.5) + seed * 6.0) * 4.5
          gx[i] = gx[i] + (gvx[i] + flutter) * dt
          gy[i] = gy[i] + (gvy[i] + bob) * dt
          gz[i] = gz[i] + (gvz[i] + flutter * 0.7) * dt
          -- A little gravity keeps wall-hit leaves sliding toward the base
          -- instead of hovering indefinitely after their horizontal bounce.
          if gvy[i] > -8.0 then gvy[i] = gvy[i] - 2.2 * dt end
        end
        if LP and LP.resolve and leafCtx then
          local allowSettle = leafSettled < leafSettleCap
          local wasSettled = grain.leafSettled[i] == true
          local result = LP.resolve(grain, i, dt, oldX, oldY, oldZ, leafCtx, windX, windZ, allowSettle)
          if result == "settled" and not wasSettled and grain.leafSettled[i] then
            leafSettled = leafSettled + 1
          elseif result == "expired-settle" then
            if wasSettled and leafSettled > 0 then leafSettled = leafSettled - 1 end
            spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, false, grain.simRadius[grainKind])
          end
        end
      else
        gx[i] = gx[i] + gvx[i] * dt
        gy[i] = gy[i] + gvy[i] * dt
        gz[i] = gz[i] + gvz[i] * dt
      end
      -- Sand volume fill recycles early (py - 3) so grit stays in the air column.
      -- Hail / ash / leaves reach the same floor plane as rain/snow deposits.
      local floorY = (grainKind == 2) and (py - 3) or groundY
      local settledLeaf = grainKind == 3 and grain.leafSettled[i] == true
      if (not settledLeaf and grain.life[i] >= grain.maxLife[i])
          or (not settledLeaf and gy[i] < floorY)
          or ((gx[i]-px)*(gx[i]-px)+(gz[i]-pz)*(gz[i]-pz)) > ((grain.simRadius[grainKind] or STREAM_RADIUS)*1.25)^2 then
        spawnGrainAt(i, px, py, pz, grainKind, windX, windZ, false, grain.simRadius[grainKind])
      end
    end
  end
  grain.active = wantGrain
  -- grain.target stays the authored logical count; simTarget is the actual Lua
  -- population and gpuTarget is the zero-upload procedural remainder.
  -- No copy/allocation is performed for these persistent tables.

end

-- ---------------------------------------------------------------------------
-- VERTEX BUFFER
-- ---------------------------------------------------------------------------
-- One persistent table-of-tables per stream, mutated in place. The previous
-- code built a fresh `verts` table and a fresh 7-field table per vertex every
-- frame — at the snow cap that is 25,200 allocations per frame before the GPU
-- sees anything. Nothing here allocates once the buffer has reached its high
-- water mark.
local RAIN_FMT = {
  { "VertexPosition", "float", 3 },
  { "RainTint", "float", 4 },
}
local SNOW_FMT = RAIN_FMT  -- one proven card layout for every 3D particle family

local Buf = {}
Buf.__index = Buf

local function newBuf()
  return setmetatable({ v = {}, cap = 0, n = 0 }, Buf)
end

function Buf:reset() self.n = 0 end

-- Grow the backing store to at least n entries. Needed because the mesh is
-- allocated with headroom past the current fill, and setVertices reads real
-- table entries -- without reserving, the mesh could only ever be created at
-- exactly the high water mark, so a fluctuating particle count reallocated the
-- VBO every time the count ticked up.
function Buf:reserve(n)
  local v = self.v
  for i = self.cap + 1, n do v[i] = { 0, 0, 0, 0, 0, 0, 0 } end
  if n > self.cap then self.cap = n end
end

function Buf:push(x, y, z, r, g, b, a)
  local n = self.n + 1
  self.n = n
  local t = self.v[n]
  if t then
    t[1], t[2], t[3], t[4], t[5], t[6], t[7] = x, y, z, r, g, b, a
  else
    self.v[n] = { x, y, z, r, g, b, a }
    self.cap = n
  end
  -- Entries past n from a previous, busier frame stay in the table untouched;
  -- they are never uploaded because the upload is a prefix of length n.
end

local rainBuf, snowBuf, wetBuf, grainBuf, gsnowBuf, faceBuf =
  newBuf(), newBuf(), newBuf(), newBuf(), newBuf(), newBuf()

-- Meshes are allocated at the buffer's high water mark and only re-created when
-- it grows, so the common case is a prefix upload into an existing VBO.
local meshCap = {}
local prefixUpload = nil   -- nil = untested, true/false = known

-- GPU/driver state cache. VP is identical for every WorldPrecip subpass in one
-- draw frame, and several passes reuse the same shader. Upload it once per
-- shader per frame. The first encounter still probes both historical host send
-- signatures; after that we use only the signature that actually worked.
local wpDrawSerial = 0
local vpSentSerial = setmetatable({}, { __mode = "k" })
local vpSendMode = setmetatable({}, { __mode = "k" })

local function sendVPOnce(sh, vp)
  if not sh or not vp then return false end
  if vpSentSerial[sh] == wpDrawSerial then return true end
  local mode = vpSendMode[sh]
  local ok = false
  if mode == "default" then
    ok = V.safeCall(sh.send, sh, "vp", vp)
  elseif mode == "row" then
    ok = V.safeCall(sh.send, sh, "vp", "row", vp)
  else
    local okRow = V.safeCall(sh.send, sh, "vp", "row", vp)
    local okDefault = V.safeCall(sh.send, sh, "vp", vp)
    if okDefault then mode, ok = "default", true
    elseif okRow then mode, ok = "row", true
    else mode, ok = false, false end
    vpSendMode[sh] = mode
  end
  if ok then vpSentSerial[sh] = wpDrawSerial end
  return ok
end

local function uploadMesh(mesh, fmt, buf)
  local n = buf.n
  if n < 3 then return nil end
  -- Central GPU batch manager owns VBO high-water allocation when available.
  -- Existing local uploader remains the fail-open compatibility path.
  local PB=particleBatcher()
  if PB and PB.upload then
    local ok,m=V.safeCall(PB.upload,mesh,fmt,buf.v,n,"stream",.35)
    if ok and m then return m end
  end
  local cap = (mesh and meshCap[mesh]) or 0
  if (not mesh) or cap < n then
    if mesh then meshCap[mesh] = nil end
    -- Grow with headroom so a slowly rising particle count does not reallocate
    -- every frame. Never past what the buffer can actually supply.
    local want = floor(n * 1.35) + 256
    buf:reserve(want)
    local ok, m = V.safeCall(love.graphics.newMesh, fmt, want, "triangles", "stream")
    if not ok or not m then return nil end
    mesh = m
    meshCap[mesh] = want
  end

  if prefixUpload ~= false then
    local ok = V.safeCall(mesh.setVertices, mesh, buf.v, 1, n)
    if ok then
      prefixUpload = true
      V.safeCall(mesh.setDrawRange, mesh, 1, n)
      return mesh
    end
    prefixUpload = false
  end

  -- Fallback host without the 3-argument setVertices: upload a slice. One table
  -- per frame instead of tens of thousands — still worth it.
  local slice = {}
  local v = buf.v
  for i = 1, n do slice[i] = v[i] end
  if not V.safeCall(mesh.setVertices, mesh, slice) then
    meshCap[mesh] = nil
    return nil
  end
  V.safeCall(mesh.setDrawRange, mesh, 1, n)
  return mesh
end

-- ---------------------------------------------------------------------------
-- SHADERS
-- ---------------------------------------------------------------------------
local function getRainShader()
  if rainShader ~= nil then return rainShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    rainShader = false
    return nil
  end
  -- Streaks used to be flat bars: this shader returned a constant colour and
  -- the vertex alpha, with no falloff anywhere, so every drop was a hard-edged
  -- opaque rectangle -- and a near one was a large hard-edged opaque rectangle.
  -- Same defect the ground-snow patches had, found the same way (rasterizing
  -- the real vertex stream and looking at it).
  --
  -- The quad's UVs now ride in .g/.b: g runs along the streak, b across it.
  -- Across gives a soft edge; along fades both ends so a drop looks like motion
  -- blur rather than a painted stick.
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // 8.1.76 CPU fallback matches the procedural water-streak silhouette:
    // thin tail, slightly fuller leading edge, feathered ends and translucent
    // blue-grey water instead of a flat white rectangle.
    float along = clamp(vCol.g, 0.0, 1.0);
    float x = abs(vCol.b * 2.0 - 1.0);
    float taper = 0.18 + 0.82 * sqrt(max(0.0, along));
    taper *= 1.0 - 0.18 * smoothstep(0.86, 1.0, along);
    float nx = x / max(0.12, taper);
    float side = 1.0 - smoothstep(0.16, 1.0, nx);
    float ends = smoothstep(0.015, 0.14, along) * (1.0 - smoothstep(0.94, 1.0, along));
    float core = 1.0 - smoothstep(0.02, 0.28, nx);
    float alpha = vCol.a * side * ends * (0.46 + 0.54 * core) * 0.82;
    vec3 water = vec3(0.62, 0.72, 0.82);
    float glint = core * smoothstep(0.62, 0.90, along) * (1.0 - smoothstep(0.92, 1.0, along));
    water = mix(water, min(vec3(1.0), water + vec3(0.10, 0.12, 0.14)), glint * 0.30);
    return vec4(water, alpha) * color;
  }
#endif
]])
  rainShader = (ok and sh) or false
  return rainShader or nil
end

-- Snow shader now uses the per-vertex tint instead of a hardcoded white, and
-- reads its soft falloff from the quad's own UVs. Two reasons: per-flake
-- brightness breaks up the "one sprite repeated 4000 times" read, and the round
-- falloff is what keeps a flake from looking like a square at close range —
-- which matters far more now that flakes routinely pass within a unit of you.

-- Universal host-safe card shader. Rain is the one family confirmed to render
-- on every target host, so all precipitation meshes now use its exact RainTint
-- attribute layout. If a richer family shader cannot compile after a driver/GLES
-- reset, this shader guarantees the particle remains visible instead of silently
-- disappearing. The specialized shader is still preferred whenever available.
local function getCardFallbackShader()
  if cardFallbackShader ~= nil then return cardFallbackShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    cardFallbackShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float d = dot(p, p);
    float a = vCol.a * (1.0 - smoothstep(0.72, 1.0, d));
    return vec4(vec3(0.72 + 0.28 * vCol.r), a) * color;
  }
#endif
]])
  cardFallbackShader = (ok and sh) or false
  return cardFallbackShader or nil
end

local function getSnowShader()
  local useBall = false
  V.safeCall(function()
    local S = V.require("Settings")
    if S and S.snowShape and S.snowShape() == "ball" then useBall = true end
  end)
  if useBall then
    if snowShaderBall ~= nil then return snowShaderBall or nil end
    if not (love and love.graphics and love.graphics.newShader) then
      snowShaderBall = false
      return nil
    end
    local okBall, shBall = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float d = dot(p, p);
    float soft = 1.0 - smoothstep(0.10, 1.0, d);
    soft = soft * soft;
    vec3 rgb = vec3(0.95, 0.97, 1.0) * (0.55 + vCol.r * 0.55);
    return vec4(rgb, vCol.a * soft) * color;
  }
#endif
]])
    snowShaderBall = (okBall and shBall) or false
    return snowShaderBall or nil
  end
  if snowShader ~= nil then return snowShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    snowShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // Dendrite snowflake: hexagonal core, 6 arms, V-branches, fine needles.
    // UVs in .g/.b; per-flake variation in .r.
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.02) discard;
    float ang = atan(p.y, p.x);
    float seed = clamp(vCol.r, 0.0, 1.0);

    // 6-fold symmetry
    float sector = 3.14159265 / 3.0;
    float a = abs(mod(ang + sector * 0.5, sector) - sector * 0.5);

    // Hex crystal core (flat sides, not a circle)
    float hex = a * 1.73205; // ~tan(60)*scaled
    float coreR = 0.11 + seed * 0.04;
    float core = 1.0 - smoothstep(coreR * 0.55, coreR, max(r, hex * r * 0.35 + r * 0.65));
    core = core * core;

    // Primary arm: tapering spine toward tip
    float armW = (0.028 + seed * 0.018) * (1.15 - r * 0.55);
    float armLen = 0.88 + seed * 0.08;
    float arm = smoothstep(armW, armW * 0.15, a * max(r, 0.03));
    arm *= 1.0 - smoothstep(armLen * 0.78, armLen, r);
    arm *= smoothstep(0.06, 0.14, r); // leave core dominant at center

    // Dendrite V-branches (angled off the main arm)
    float brAng = 0.55 + seed * 0.25;
    float br1r = 0.28 + seed * 0.10;
    float br2r = 0.50 + seed * 0.08;
    float br3r = 0.68 + seed * 0.05;

    // Distance to a branch line that leaves the arm at brAng
    float ba = a - (r - br1r) * brAng * 0.35;
    float branch1 = smoothstep(0.05, 0.012, abs(ba))
      * smoothstep(0.05, 0.0, abs(r - br1r) - 0.12)
      * (1.0 - smoothstep(0.82, 0.98, r));
    ba = a - (r - br2r) * brAng * 0.40;
    float branch2 = smoothstep(0.045, 0.01, abs(ba))
      * smoothstep(0.05, 0.0, abs(r - br2r) - 0.11)
      * (1.0 - smoothstep(0.82, 0.98, r));
    ba = a - (r - br3r) * (brAng * 0.45);
    float branch3 = smoothstep(0.04, 0.01, abs(ba))
      * smoothstep(0.04, 0.0, abs(r - br3r) - 0.09)
      * (1.0 - smoothstep(0.85, 1.0, r));

    // Fine needles near tips
    float needle = smoothstep(0.022, 0.006, a * r)
      * smoothstep(0.62, 0.78, r)
      * (1.0 - smoothstep(0.90, 1.0, r));

    // Soft frost halo (very faint)
    float frost = (1.0 - smoothstep(0.0, 0.95, r)) * 0.12 * (0.5 + seed * 0.5);

    float shape = max(core, arm);
    shape = max(shape, branch1 * 0.85);
    shape = max(shape, branch2 * 0.80);
    shape = max(shape, branch3 * 0.70);
    shape = max(shape, needle * 0.55);
    shape = max(shape, frost);

    // Outer mask — no square quad edges
    float mask = 1.0 - smoothstep(0.90, 1.02, r);
    shape *= mask;

    // Cool crystalline tint; brighter arms, softer core
    vec3 ice = mix(vec3(0.82, 0.90, 1.0), vec3(1.0, 1.0, 1.0), 0.35 + seed * 0.50);
    vec3 rgb = ice * (0.70 + shape * 0.45);
    float alpha = vCol.a * clamp(shape, 0.0, 1.0);
    if (alpha < 0.02) discard;
    return vec4(rgb, alpha) * color;
  }
#endif
]])
  snowShader = (ok and sh) or false
  return snowShader or nil
end


-- GPU-instanced equivalent of the snow card. It intentionally carries the
-- exact same physical inputs as drawSnowFlakes' CPU billboard path:
-- centre, tumble angle, authored size/alpha/brightness, and lifetime fraction.
-- Camera-facing axes, distance scaling and roll happen in the vertex shader.
-- This changes submission cost, not particle count or visual quality.
function snowInstance.shaderFor(useBall)
  local cached=useBall and snowInstance.shaderBall or snowInstance.shader
  if cached~=nil then return cached or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    if useBall then snowInstance.shaderBall=false else snowInstance.shader=false end
    return nil
  end
  local pixel
  if useBall then
    pixel=[[
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float d = dot(p, p);
    float soft = 1.0 - smoothstep(0.10, 1.0, d);
    soft = soft * soft;
    vec3 rgb = vec3(0.95, 0.97, 1.0) * (0.55 + vCol.r * 0.55);
    return vec4(rgb, vCol.a * soft) * color;
  }
#endif
]]
  else
    pixel=[[
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.02) discard;
    float ang = atan(p.y, p.x);
    float seed = clamp(vCol.r, 0.0, 1.0);
    float sector = 3.14159265 / 3.0;
    float a = abs(mod(ang + sector * 0.5, sector) - sector * 0.5);
    float hex = a * 1.73205;
    float coreR = 0.11 + seed * 0.04;
    float core = 1.0 - smoothstep(coreR * 0.55, coreR, max(r, hex * r * 0.35 + r * 0.65));
    core = core * core;
    float armW = (0.028 + seed * 0.018) * (1.15 - r * 0.55);
    float armLen = 0.88 + seed * 0.08;
    float arm = smoothstep(armW, armW * 0.15, a * max(r, 0.03));
    arm *= 1.0 - smoothstep(armLen * 0.78, armLen, r);
    arm *= smoothstep(0.06, 0.14, r);
    float brAng = 0.55 + seed * 0.25;
    float br1r = 0.28 + seed * 0.10;
    float br2r = 0.50 + seed * 0.08;
    float br3r = 0.68 + seed * 0.05;
    float ba = a - (r - br1r) * brAng * 0.35;
    float branch1 = smoothstep(0.05, 0.012, abs(ba))
      * smoothstep(0.05, 0.0, abs(r - br1r) - 0.12)
      * (1.0 - smoothstep(0.82, 0.98, r));
    ba = a - (r - br2r) * brAng * 0.40;
    float branch2 = smoothstep(0.045, 0.01, abs(ba))
      * smoothstep(0.05, 0.0, abs(r - br2r) - 0.11)
      * (1.0 - smoothstep(0.82, 0.98, r));
    ba = a - (r - br3r) * (brAng * 0.45);
    float branch3 = smoothstep(0.04, 0.01, abs(ba))
      * smoothstep(0.04, 0.0, abs(r - br3r) - 0.09)
      * (1.0 - smoothstep(0.85, 1.0, r));
    float needle = smoothstep(0.022, 0.006, a * r)
      * smoothstep(0.62, 0.78, r)
      * (1.0 - smoothstep(0.90, 1.0, r));
    float frost = (1.0 - smoothstep(0.0, 0.95, r)) * 0.12 * (0.5 + seed * 0.5);
    float shape = max(core, arm);
    shape = max(shape, branch1 * 0.85);
    shape = max(shape, branch2 * 0.80);
    shape = max(shape, branch3 * 0.70);
    shape = max(shape, needle * 0.55);
    shape = max(shape, frost);
    float mask = 1.0 - smoothstep(0.90, 1.02, r);
    shape *= mask;
    vec3 ice = mix(vec3(0.82, 0.90, 1.0), vec3(1.0, 1.0, 1.0), 0.35 + seed * 0.50);
    vec3 rgb = ice * (0.70 + shape * 0.45);
    float alpha = vCol.a * clamp(shape, 0.0, 1.0);
    if (alpha < 0.02) discard;
    return vec4(rgb, alpha) * color;
  }
#endif
]]
  end
  local vertex=[[
#ifdef VERTEX
  extern mat4 vp;
  extern vec3 snowEye;
  extern float snowDepth;
  attribute vec4 SnowInstanceA; // x,y,z,roll
  attribute vec4 SnowInstanceB; // size,alpha,brightness,lifeT
  varying vec4 vCol;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 center=SnowInstanceA.xyz;
    float roll=SnowInstanceA.w;
    float size=SnowInstanceB.x;
    float alpha=SnowInstanceB.y;
    float br=SnowInstanceB.z;
    float lifeT=SnowInstanceB.w;
    if (lifeT < 0.08) alpha *= lifeT / 0.08;
    if (lifeT > 0.90) alpha *= max(0.0, 1.0 - (lifeT - 0.90) / 0.10);
    vec3 toEye=snowEye-center;
    float dist=max(0.0001,length(toEye));
    vec3 dir=toEye/dist;
    float nearMix=1.0-clamp(dist/max(0.001,snowDepth),0.0,1.0);
    size *= 0.50 + nearMix * 1.15;
    alpha *= 0.30 + nearMix * 0.70;
    vec3 right=vec3(-dir.z,0.0,dir.x);
    float rl=length(right);
    if (rl < 0.0001) right=vec3(1.0,0.0,0.0); else right/=rl;
    vec3 up=cross(dir,right);
    float ul=length(up);
    if (ul < 0.0001) up=vec3(0.0,1.0,0.0); else up/=ul;
    float ca=cos(roll), sa=sin(roll);
    vec3 axisX=(right*ca + up*sa)*(size*0.55);
    vec3 axisY=(up*ca - right*sa)*(size*0.55);
    vec2 corner=vertex_position.xy;
    vec3 world=center + axisX*corner.x + axisY*corner.y;
    vec2 uv=vec2(corner.x*0.5+0.5, 0.5-corner.y*0.5);
    vCol=vec4(br,uv.x,uv.y,alpha);
    return vp*vec4(world,1.0);
  }
#endif
]]
  local ok,sh=V.safeCall(love.graphics.newShader,vertex..pixel)
  if useBall then snowInstance.shaderBall=(ok and sh) or false else snowInstance.shader=(ok and sh) or false end
  return (ok and sh) or nil
end

function snowInstance.ensureMeshes()
  if snowInstance.failed then return false end
  local g=love and love.graphics
  if not (g and g.newMesh and g.drawInstanced) then return false end
  if not snowInstance.base then
    local baseFmt={{"VertexPosition","float",3}}
    local baseVerts={{-1,1,0},{1,1,0},{1,-1,0},{-1,1,0},{1,-1,0},{-1,-1,0}}
    local ok,b=V.safeCall(g.newMesh,baseFmt,baseVerts,"triangles","static")
    if not ok or not b or type(b.attachAttribute)~="function" then snowInstance.failed=true; return false end
    snowInstance.base=b
  end
  local chunk=snowInstance.chunk or 8192
  if not snowInstance.instances then
    local fmt={{"SnowInstanceA","float",4},{"SnowInstanceB","float",4}}
    local ok,m=V.safeCall(g.newMesh,fmt,chunk,"points","stream")
    if not ok or not m then snowInstance.failed=true; return false end
    local okA=V.safeCall(snowInstance.base.attachAttribute,snowInstance.base,"SnowInstanceA",m,"perinstance")
    local okB=V.safeCall(snowInstance.base.attachAttribute,snowInstance.base,"SnowInstanceB",m,"perinstance")
    if not (okA and okB) then snowInstance.failed=true; return false end
    snowInstance.instances=m; snowInstance.cap=chunk
  end
  for i=snowInstance.rowCap+1,chunk do snowInstance.rows[i]={0,0,0,0,0,0,0,0} end
  snowInstance.rowCap=chunk
  return true
end


-- Declared before drawGrains uses it. In the previous file this sat *below*
-- drawGrains, so the call resolved to a nil global and threw every frame.
-- HAIL. Snow and hail are both white, so the difference has to be entirely in
-- the EDGE and the motion. The shared snow shader fades over a wide radius,
-- which is what makes a flake a soft smudge -- run hail through it and you get
-- small snowflakes, which is exactly what it looked like.
--
-- This is a hard disc: opaque to nearly the full radius, then a one-step rim so
-- it is round rather than square. Plus a bright off-centre highlight, which is
-- what sells a lump of ice over a dot of paint.
local hailShader
local ashShader
local function getHailShader()
  if hailShader ~= nil then return hailShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    hailShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float d = length(p);
    // Hard body with a narrow antialiased rim -- not snow's wide falloff.
    float body = 1.0 - smoothstep(0.78, 1.0, d);
    // Off-centre specular: a wet ice highlight.
    float spec = 1.0 - smoothstep(0.0, 0.42, length(p - vec2(-0.30, -0.30)));
    vec3 rgb = vec3(0.88, 0.93, 1.0) + vec3(0.12, 0.07, 0.0) * spec;
    return vec4(rgb, vCol.a * body) * color;
  }
#endif
]])
  hailShader = (ok and sh) or false
  return hailShader or nil
end

local function getAshShader()
  if ashShader ~= nil then return ashShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    ashShader = false
    return nil
  end
  -- Three distinct ash silhouettes (selected by seed ranges):
  --   0 = jagged torn-paper flake
  --   1 = elongated cinder / splinter
  --   2 = chunky ember with burnt holes
  -- Same proven card layout as rain/snow (position + RainTint); UVs in .g/.b, seed in .r.
  -- .r must carry the full 0..1 seed (not a compressed brightness) so all three
  -- shapes are reached. Tint comes from love.graphics.setColor (grey/black pass).
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.12) discard;
    float ang = atan(p.y, p.x);
    float seed = clamp(vCol.r, 0.0, 1.0);
    // Secondary jitter so particles of the same shape still differ slightly
    float j = fract(seed * 7.13 + 0.17);

    float shape = 0.0;

    if (seed < 0.333) {
      // ---- Shape 0: irregular torn-paper flake (odd harmonics only) ----
      // Avoid even angular frequencies (2/4/8) — those form an X / cross.
      // 3 + 5 + 7 lobes keep the silhouette asymmetric and paper-like.
      float w1 = sin(ang * 3.0 + j * 5.1);
      float w2 = sin(ang * 5.0 - j * 3.7 + 1.2);
      float w3 = sin(ang * 7.0 + j * 2.4 - 0.8);
      float rim = 0.62 + 0.20 * w1 + 0.14 * w2 + 0.09 * w3;
      rim = clamp(rim, 0.40, 0.96);
      float edge = 1.0 - smoothstep(rim * 0.74, rim, r);
      // Soft edge roughness (no through-cuts that read as an X)
      float rough = sin(ang * 5.0 + j * 8.0) * sin(r * 7.0 - j * 4.0);
      rough = smoothstep(0.15, 0.55, abs(rough)) * smoothstep(0.25, 0.70, r);
      edge *= 1.0 - rough * 0.28;
      // Small off-centre pinhole, not a diametric slash
      float hole = sin((ang + j * 2.3) * 3.0) * sin(r * 8.0 - j * 5.0);
      hole = smoothstep(0.45, 0.82, hole) * smoothstep(0.15, 0.42, r);
      edge *= 1.0 - hole * 0.40;
      float mask = 1.0 - smoothstep(0.88, 1.08, r);
      shape = edge * mask;
    } else if (seed < 0.666) {
      // ---- Shape 1: elongated cinder / charcoal splinter ----
      // Squeeze toward a long axis so it reads as a stick, not a flake
      vec2 q = vec2(p.x * 1.55, p.y * 0.72);
      float rr = length(q);
      if (rr > 1.10) discard;
      float aang = atan(q.y, q.x);
      float w1 = sin(aang * 2.0 + j * 4.0);
      float w2 = sin(aang * 5.0 - j * 3.2);
      float rim = 0.70 + 0.18 * w1 + 0.10 * w2;
      rim = clamp(rim, 0.48, 0.95);
      float edge = 1.0 - smoothstep(rim * 0.75, rim, rr);
      // Char cracks along the long axis
      float crack = abs(sin(q.x * 9.0 + j * 8.0));
      crack = 1.0 - smoothstep(0.02, 0.14, crack);
      crack *= smoothstep(0.10, 0.50, rr) * (1.0 - smoothstep(0.70, 0.95, rr));
      edge *= 1.0 - crack * 0.45;
      // Tapered tips
      float tip = smoothstep(0.85, 1.05, abs(q.x));
      edge *= 1.0 - tip * 0.35;
      float mask = 1.0 - smoothstep(0.90, 1.10, rr);
      shape = edge * mask;
    } else {
      // ---- Shape 2: chunky ember with large burnt voids ----
      float w1 = sin(ang * 2.0 + j * 5.5);
      float w2 = sin(ang * 3.0 - j * 2.8);
      float rim = 0.72 + 0.16 * w1 + 0.10 * w2;
      rim = clamp(rim, 0.50, 0.96);
      float edge = 1.0 - smoothstep(rim * 0.78, rim, r);
      // Large irregular burnt holes (charred coal look)
      float hole1 = sin(ang * 3.0 + j * 7.0) * sin(r * 6.0 - j * 4.0);
      hole1 = smoothstep(0.25, 0.70, hole1) * smoothstep(0.10, 0.38, r);
      float hole2 = sin(ang * 5.0 - j * 5.5) * sin(r * 8.0 + j * 3.0);
      hole2 = smoothstep(0.35, 0.78, hole2) * smoothstep(0.18, 0.48, r);
      edge *= 1.0 - hole1 * 0.70 - hole2 * 0.45;
      // Soft outer mask
      float mask = 1.0 - smoothstep(0.88, 1.08, r);
      shape = edge * mask;
    }

    if (shape < 0.02) discard;
    return vec4(1.0, 1.0, 1.0, vCol.a * shape) * color;
  }
#endif
]])
  ashShader = (ok and sh) or false
  return ashShader or nil
end


-- ---------------------------------------------------------------------------
-- LEAF SHADER
-- ---------------------------------------------------------------------------
-- Leaves were drawing through the snow shader: a soft radial blob tinted green.
-- That is why they read as coloured discs rather than leaves. A leaf is not a
-- blob -- it is a SILHOUETTE with a point, a midrib and a lit side, and those
-- three things are what the eye actually uses to recognise one at a glance.
--
-- Carved procedurally from the quad UV, so there is no texture to ship and it
-- stays sharp at any size:
--
--   * OVATE OUTLINE. Half-width follows sin(pi*v) raised to a power, which
--     gives a rounded base and a drawn-out tip rather than an ellipse. Skewed
--     slightly along its length so the widest point sits below centre, as on a
--     real leaf, and given a small asymmetry per leaf so no two are identical.
--   * MIDRIB. A darker line down the centre, tapering to nothing at the tip.
--   * SIDE VEINS. Faint chevrons angled from the midrib toward the tip. Kept
--     very low contrast -- at these sizes they read as texture, not stripes.
--   * CURL SHADING. A soft light-to-dark gradient across the blade so the leaf
--     looks like a curved surface catching light rather than a flat cutout,
--     plus a brighter rim on the lit edge.
--   * A short STALK at the base, which is a surprisingly strong cue.
--
-- The blade colour comes from setColor (the LEAF COLOR menu). vCol.r carries
-- per-leaf brightness so a drift of leaves varies in tone; .g/.b are the quad
-- UV; .a is the fade.
local leafShader
local function getLeafShader()
  if leafShader ~= nil then return leafShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    leafShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  // MUST be RainTint: that is the attribute name in the shared grain vertex
  // format (see SNOW_FMT). Declaring `LeafTint` named an attribute the mesh
  // does not have, so the shader received no per-vertex data and leaves stopped
  // appearing entirely. Every other grain shader here reads RainTint for the
  // same reason -- the name is the format's, not the effect's.
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float u = vCol.g;              // across the blade, 0..1
    float v = vCol.b;              // base (0) to tip (1)
    float bright = vCol.r;

    // Per-leaf variation, stable for this leaf because brightness is stable.
    float wob = (bright - 0.85) * 2.0;

    // --- outline -----------------------------------------------------------
    // Rounded at the base, drawn out to a point at the tip.
    float t = clamp(v, 0.0, 1.0);
    float halfW = pow(sin(3.14159 * t), 0.62) * (1.0 - 0.22 * t);
    // Widest point below centre, and a slight lean so it is not symmetrical.
    halfW *= 1.0 + 0.18 * (0.5 - t);
    float centre = 0.5 + 0.06 * wob * sin(3.14159 * t);
    float d = abs(u - centre);
    // NO fwidth(). Screen-space derivatives need GL_OES_standard_derivatives
    // on GLES targets, and where that is unavailable the shader fails to
    // COMPILE -- which here is silent, because newShader is protected-call wrapped and
    // the caller just falls through. This was the only fwidth in the file;
    // every other shader uses a constant edge, and so does this one now.
    //
    // A fixed width is also fine visually: leaf quads are small on screen, so
    // an adaptive edge was buying almost nothing.
    float edge = 0.018;
    float blade = 1.0 - smoothstep(halfW * 0.5 - edge, halfW * 0.5 + edge, d);

    // --- stalk -------------------------------------------------------------
    float stalk = (1.0 - smoothstep(0.010, 0.022, abs(u - centre)))
                * (1.0 - smoothstep(0.0, 0.10, t));
    float mask = clamp(blade + stalk, 0.0, 1.0);
    if (mask < 0.01) discard;

    // --- shading -----------------------------------------------------------
    vec3 base = color.rgb * (0.72 + bright * 0.42);
    // Curl: one side of the blade catches the light.
    float across = (u - centre) / max(halfW * 0.5, 1e-3);
    float lit = 0.78 + 0.42 * smoothstep(-1.0, 1.0, across);
    // Slightly darker and warmer toward the base, as leaves are.
    lit *= 0.90 + 0.16 * t;
    vec3 rgb = base * lit;

    // Midrib, tapering out before the tip.
    float rib = (1.0 - smoothstep(0.006, 0.020, abs(u - centre)))
              * (1.0 - smoothstep(0.55, 0.97, t));
    rgb = mix(rgb, base * 0.55, rib * 0.75);

    // Side veins: chevrons angled toward the tip. Deliberately faint.
    float veinPhase = (t * 7.0) - abs(across) * 1.6;
    float vein = smoothstep(0.86, 1.0, abs(fract(veinPhase) * 2.0 - 1.0));
    rgb = mix(rgb, base * 0.74, vein * 0.22 * blade);

    // Rim light on the lit edge picks the silhouette out against the sky.
    float rim = smoothstep(halfW * 0.5 - 0.05, halfW * 0.5, d);
    rgb += base * rim * 0.28;

    // The stalk is woody, not blade-coloured.
    rgb = mix(rgb, base * 0.42, stalk * (1.0 - blade));

    return vec4(rgb, vCol.a * mask) * vec4(1.0, 1.0, 1.0, color.a);
  }
#endif
]])
  leafShader = (ok and sh) or false
  return leafShader or nil
end

local function getGrainShader()
  if grainShader ~= nil then return grainShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    grainShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return vec4(vCol.rgb, vCol.a) * color;
  }
#endif
]])
  grainShader = (ok and sh) or false
  return grainShader or nil
end

-- Soft disc for sand/dust. Do NOT use the snowflake dendrite shader here:
-- dendrite discards most of each quad (arms only), so grit was invisible at
-- steep voxel angles and weak in other views.
local sandShader = nil
local function getSandShader()
  if sandShader ~= nil then return sandShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    sandShader = false
    return nil
  end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 RainTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = RainTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vec2(vCol.g, vCol.b) * 2.0 - 1.0;
    float d = dot(p, p);
    float soft = 1.0 - smoothstep(0.08, 1.0, d);
    soft = soft * soft;
    float br = 0.55 + vCol.r * 0.55;
    return vec4(br, br, br, vCol.a * soft) * color;
  }
#endif
]])
  sandShader = (ok and sh) or false
  return sandShader or nil
end

local function beginPass(Voxel3D, sh)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  local began = false
  if Voxel3D.beginEffect and sh then began = Voxel3D.beginEffect(sh) end
  if sh then
    if not began then V.safeCall(love.graphics.setShader, sh) end
    sendVPOnce(sh, Voxel3D.vp)
  end
end

local function endPass(Voxel3D)
  if Voxel3D.endEffect then V.safeCall(Voxel3D.endEffect)
  else V.safeCall(love.graphics.setShader) end
  V.safeCall(love.graphics.setDepthMode, "lequal", true)
end

-- ---------------------------------------------------------------------------
-- CAMERA VISIBILITY
-- ---------------------------------------------------------------------------
-- Simulation remains full 360 degrees, but geometry wholly behind the camera
-- can never contribute a pixel. Skip only that guaranteed-invisible hemisphere
-- before billboard construction/GPU upload. A generous rear margin preserves
-- streaks/cards that straddle the near plane. This changes cost, not output.
local function cameraForward(Voxel3D, ex, ey, ez)
  if not Voxel3D then return nil, nil, nil end

  -- Current voxel/FPV hosts publish the actual horizontal camera heading as
  -- lookFlat. Prefer it over `focus`: on several hosts focus is the player/world
  -- anchor (often the avatar's feet), not a look target. Treating that anchor as
  -- the camera vector points almost straight down in first person and used to
  -- classify every cloud-bank drop above the player as "behind" the camera.
  local lf = Voxel3D.lookFlat
  if type(lf) == "table" then
    local fx, fz = tonumber(lf[1]), tonumber(lf[3])
    if fx and fz then
      local fl2 = fx * fx + fz * fz
      if fl2 > 1e-8 then
        local inv = 1.0 / sqrt(fl2)
        return fx * inv, 0, fz * inv
      end
    end
  end

  -- Some hosts expose a true 3D camera-forward vector instead. Use it when
  -- present, but never invent one from an opaque object.
  local cam = Voxel3D.camera
  local cf = cam and (cam.forward or cam.look)
  if type(cf) == "table" then
    local fx, fy, fz = tonumber(cf[1]), tonumber(cf[2]), tonumber(cf[3])
    if fx and fy and fz then
      local fl2 = fx * fx + fy * fy + fz * fz
      if fl2 > 1e-8 then
        local inv = 1.0 / sqrt(fl2)
        return fx * inv, fy * inv, fz * inv
      end
    end
  end

  -- Legacy orbit hosts may only publish eye + focus. Use that pair only when it
  -- is clearly a horizontal-ish view ray. If it is mostly vertical, focus is
  -- almost certainly the world/player anchor; disabling CPU rear-culling is
  -- safer and visually correct because the GPU frustum still clips geometry.
  local f = Voxel3D.focus
  if type(f) ~= "table" then return nil, nil, nil end
  local fx, fy, fz = (tonumber(f[1]) or 0) - ex, (tonumber(f[2]) or 0) - ey, (tonumber(f[3]) or 0) - ez
  local horiz2 = fx * fx + fz * fz
  local fl2 = horiz2 + fy * fy
  if fl2 < 1e-8 or horiz2 < fl2 * 0.0625 then return nil, nil, nil end
  local inv = 1.0 / sqrt(fl2)
  return fx * inv, fy * inv, fz * inv
end

local celestialEngineCached=false
local function celestialEngine()
  if celestialEngineCached~=false then return celestialEngineCached end
  local ok,E=V.safeCall(V.require,"CelestialEngine")
  if ok and E then celestialEngineCached=E; return E end
  -- Keep `false` so a startup/load-order miss can recover on a later frame.
  return nil
end
local function celestialTint(kind, r, g, b)
  local E=celestialEngine()
  if E and E.particleTint then
    local ok2,tr,tg,tb=V.safeCall(E.particleTint,kind)
    if ok2 and type(tr)=="number" then return (r or 1)*tr,(g or 1)*tg,(b or 1)*tb end
  end
  return r or 1,g or 1,b or 1
end


function snowInstance.draw(Voxel3D,active,ex,ey,ez)
  if active<=0 or snowInstance.failed then return false,nil end
  if not snowInstance.ensureMeshes() then return false,nil end
  local useBall=false
  V.safeCall(function() local S=V.require("Settings"); useBall=S and S.snowShape and S.snowShape()=="ball" or false end)
  local sh=snowInstance.shaderFor(useBall)
  if not sh then return false,nil end
  local ax,ay,az=snow.x,snow.y,snow.z
  local asize,aa,alife,amax=snow.size,snow.a,snow.life,snow.maxLife
  local arot,abr=snow.rot,snow.br
  local CULL2=SNOW_DRAW_RADIUS*SNOW_DRAW_RADIUS
  local rows=snowInstance.rows; local chunk=snowInstance.chunk or 8192
  local PB=particleBatcher(); local n,total=0,0
  beginPass(Voxel3D,sh)
  WP._procScratch.snowEye[1],WP._procScratch.snowEye[2],WP._procScratch.snowEye[3]=ex,ey,ez
  V.safeCall(sh.send,sh,"snowEye",WP._procScratch.snowEye)
  V.safeCall(sh.send,sh,"snowDepth",SNOW_DRAW_RADIUS*1.15)
  local tr,tg,tb=celestialTint("snow",1,1,1); V.safeCall(love.graphics.setColor,tr,tg,tb,1)
  local function flush()
    if n<=0 then return true end
    local okSet=V.safeCall(snowInstance.instances.setVertices,snowInstance.instances,rows,1,n)
    if not okSet then return false end
    local okDraw
    if PB and PB.draw then local ok,v=V.safeCall(PB.draw,snowInstance.base,n); okDraw=ok and v==true
    else okDraw=V.safeCall(love.graphics.drawInstanced,snowInstance.base,n) end
    if okDraw then total=total+n end
    n=0
    return okDraw
  end
  for i=1,active do
    local x,y,z=ax[i],ay[i],az[i]
    local dx,dy,dz=ex-x,ey-y,ez-z
    local t2=dx*dx+dy*dy+dz*dz
    if t2<CULL2 and t2>1e-6 then
      n=n+1; local r=rows[n]
      r[1],r[2],r[3],r[4]=x,y,z,arot[i] or 0
      r[5],r[6],r[7],r[8]=asize[i],aa[i],abr[i] or 1,alife[i]/max(.05,amax[i])
      if n==chunk and not flush() then endPass(Voxel3D); snowInstance.failed=true; return false,nil end
    end
  end
  local okFinal=flush()
  endPass(Voxel3D)
  if not okFinal then snowInstance.failed=true; return false,nil end
  return true,total
end


-- ---------------------------------------------------------------------------
-- DRAW: RAIN STREAKS (geometry unchanged)
-- ---------------------------------------------------------------------------
local function drawRainStreaks(Voxel3D)
  drawnRainVerts = 0
  drawnRainHealthy = false
  local logicalActive=rain.active or 0
  local active=rain.simActive or logicalActive
  if logicalActive <= 0 or not (Voxel3D and Voxel3D.vp) then return end
  local eye = Voxel3D.eye
  local ex, ey, ez = eye and (eye[1] or 0) or 0, eye and (eye[2] or 0) or 0, eye and (eye[3] or 0) or 0
  local buf = rainBuf
  buf:reset()
  local fullGPU=rain.gpuFullVisual==true

  local ax, ay, az = rain.x, rain.y, rain.z
  local avx, avy, avz = rain.vx, rain.vy, rain.vz
  local asize, aa, alife, amax = rain.size, rain.a, rain.life, rain.maxLife
  local DEPTH = STREAM_RADIUS * 1.15

  if not fullGPU then
  for i = 1, active do
    local x, y, z = ax[i], ay[i], az[i]
    local size = asize[i]
    local a = aa[i]
    local lifeT = alife[i] / max(0.05, amax[i])
    if lifeT < 0.08 then a = a * (lifeT / 0.08) end
    if lifeT > 0.85 then a = a * (1 - (lifeT - 0.85) / 0.15) end
    local tx, ty, tz = ex - x, ey - y, ez - z
    -- 8.1.77: CPU fallback rain is never view-direction culled. GPU clipping
    -- handles true rear geometry; a camera turn cannot erase the storm.
    local tl = sqrt(tx * tx + ty * ty + tz * tz)
    if tl >= 1e-3 then
      local near = 1.0 - min(1.0, tl / DEPTH)
      size = size * (0.40 + near * 1.35)
      a = a * (0.35 + near * 0.65)
      -- Drops within a couple of units of the eye projected to enormous solid
      -- bars -- one measured 9,430 px, a slab across a twelfth of the frame.
      -- A drop that close is not resolvable in reality either; fade it out
      -- rather than let it wipe the screen.
      if tl < 3.0 then a = a * (tl / 3.0) end
      local rx, rz = -tz, tx
      local rl = sqrt(rx * rx + rz * rz)
      if rl < 1e-4 then rx, rz = 1, 0 else rx, rz = rx / rl, rz / rl end
      -- Rain streak along velocity
      local vx, vy, vz = avx[i], avy[i], avz[i]
      local vl = sqrt(vx * vx + vy * vy + vz * vz)
      if vl < 1e-3 then vx, vy, vz = 0, -1, 0 else vx, vy, vz = vx / vl, vy / vl, vz / vl end
      -- Perspective-safe near rain. Keep every drop, but a streak only a few
      -- world units from the eye must not expand into a full-height screen
      -- slab. Shrink its geometric streak length/width smoothly as it enters
      -- the near field; density and logical particle count are unchanged.
      local closeLen = max(0.20, min(1.0, tl / 14.0))
      local closeWidth = max(0.35, min(1.0, tl / 9.0))
      local len = size * 3.35 * closeLen
      local half = size * 0.070 * closeWidth
      local hx, hy, hz = x - vx * len * 0.5, y - vy * len * 0.5, z - vz * len * 0.5
      local tx2, ty2, tz2 = x + vx * len * 0.5, y + vy * len * 0.5, z + vz * len * 0.5
      local hrx, hrz = rx * half, rz * half
      -- UVs: .g along the streak (0 at tail, 1 at head), .b across it.
      -- br stays in .r for format symmetry with snow.
      buf:push(hx - hrx, hy, hz - hrz, 1, 0, 0, a)
      buf:push(hx + hrx, hy, hz + hrz, 1, 0, 1, a)
      buf:push(tx2 + hrx, ty2, tz2 + hrz, 1, 1, 1, a)
      buf:push(hx - hrx, hy, hz - hrz, 1, 0, 0, a)
      buf:push(tx2 + hrx, ty2, tz2 + hrz, 1, 1, 1, a)
      buf:push(tx2 - hrx, ty2, tz2 - hrz, 1, 1, 0, a)
    end
  end

  end -- CPU near visual loop

  local nearHealthy=fullGPU
  local nearVerts=0
  -- Without view-direction culling, a non-empty CPU rain pool is expected to
  -- submit geometry. Unexpected emptiness is unhealthy so the 2D safety layer
  -- can take ownership instead of falsely claiming a healthy 3D pass.
  if not fullGPU then
  if buf.n < 3 then
    nearHealthy=(active <= 0)
  else
    rainMesh = uploadMesh(rainMesh, RAIN_FMT, buf)
    if rainMesh then
      beginPass(Voxel3D, getRainShader())
      local tr,tg,tb=celestialTint("rain",1,1,1)
      V.safeCall(love.graphics.setColor,tr,tg,tb,1)
      local okDraw = V.safeCall(love.graphics.draw, rainMesh)
      endPass(Voxel3D)
      if okDraw then nearVerts=buf.n;nearHealthy=true end
    end
  end
  end -- CPU near upload/draw

  -- Decouple visible rain phase from gameplay/update cadence. Map-edge streaming
  -- and turn states can stall update for a beat; wall-clock phase prevents the
  -- whole procedural storm from visibly slowing/freezing during that hitch.
  local rainTime=WP._rainVisualTime()
  -- First eligible frame proves the shared procedural renderer invisibly while
  -- the complete CPU path is still present. Full visual ownership begins only
  -- on a later update after this real draw succeeds.
  if not fullGPU and logicalActive>0 then
    local PP=WP._proceduralPrecipModule();local st=(PP and PP.stats and PP.stats()) or nil
    if PP and PP.probe and (not st or (not st.proven and not st.failed)) then
      local focus=lastStreamFocus or WP._procScratch.zero3
      local o=WP._procVectors(WP._procScratch.rainProbe,ex,ey,ez,rain.lastWindX,rain.lastWindZ,1,1,1)
      o.kind="rain";o.focus=focus;o.nearRadius=1.5;o.farRadius=STREAM_RADIUS
      o.topY=precipDeckY or ((focus[2] or 0)+RAIN_CEIL*WP._cloudHeightScale());o.bottomY=(rain.fieldBottomY or ((focus[2] or 0)-GROUND_DROP-32))
      o.span=precipDeckSpan or RAIN_CEIL_SPAN;o.time=rainTime;o.intensity=rain.lastIntensity or 0
      o.uniformField=WP._uniformPrecipField==true;o.worldGrid=WP._uniformPrecipField==true
      V.safeCall(PP.probe,Voxel3D,o)
    end
  end
  local farHealthy=true;local farDrawn=0;local farCount=rain.gpuActive or 0
  if farCount>0 then
    local PP=WP._proceduralPrecipModule()
    if not(PP and PP.draw)then farHealthy=false else
      local tr,tg,tb=celestialTint("rain",1,1,1);local focus=lastStreamFocus or WP._procScratch.zero3
      local o=WP._procVectors(WP._procScratch.rainDraw,ex,ey,ez,rain.lastWindX,rain.lastWindZ,tr,tg,tb)
      o.kind="rain";o.count=farCount;o.focus=focus;o.nearRadius=fullGPU and 1.5 or (rain.simRadius or 96);o.farRadius=STREAM_RADIUS
      o.topY=precipDeckY or ((focus[2] or 0)+RAIN_CEIL*WP._cloudHeightScale());o.bottomY=(rain.fieldBottomY or ((focus[2] or 0)-GROUND_DROP-32))
      o.span=precipDeckSpan or RAIN_CEIL_SPAN;o.time=rainTime;o.intensity=rain.lastIntensity or 0
      o.uniformField=WP._uniformPrecipField==true;o.worldGrid=WP._uniformPrecipField==true
      local ok,healthy,count=V.safeCall(PP.draw,Voxel3D,o)
      farHealthy=ok and healthy==true and (tonumber(count)or 0)==farCount;farDrawn=tonumber(count)or 0
    end
  end
  drawnRainVerts=nearVerts+farDrawn*6;drawnRainHealthy=nearHealthy and farHealthy
end

-- ---------------------------------------------------------------------------
-- DRAW: SNOW
-- ---------------------------------------------------------------------------
-- Each flake is a camera-facing quad *rotated by its own tumble angle* around
-- the view axis. The tumble was already simulated and previously discarded,
-- which is why every flake looked like the same stamp.
--
-- The quad UVs travel in the tint's g/b channels rather than a texture coord
-- pair, because this vertex format is position + one vec4 and adding a third
-- attribute would mean a second format and a second mesh for no gain.
local function drawSnowFlakes(Voxel3D)
  drawnSnowVerts = 0
  drawnSnowHealthy = false
  local logicalActive=snow.active or 0
  local active=snow.simActive or logicalActive
  if logicalActive <= 0 or not (Voxel3D and Voxel3D.vp) then return end
  local eye = Voxel3D.eye
  local ex, ey, ez = eye and (eye[1] or 0) or 0, eye and (eye[2] or 0) or 0, eye and (eye[3] or 0) or 0
  local fullGPU=snow.gpuFullVisual==true
  local snowTime=WP._snowVisualTime()
  -- 8.2.2: prove the procedural backend BEFORE constructing the legacy visible
  -- CPU field.  The old order guaranteed one huge per-flake Lua integration +
  -- dynamic mesh upload whenever snow started, even on a perfectly capable GPU.
  -- More importantly, drivers without instancing can now prove the immutable
  -- static-page shader fallback here and never enter the CPU hot path at all.
  if logicalActive>0 and not fullGPU then
    local PS=WP._proceduralSnowModule()
    local st=(PS and PS.stats and PS.stats()) or nil
    if PS and PS.probe and (not st or (not st.proven and not st.failed)) then
      local focus=lastStreamFocus or WP._procScratch.zero3
      local bottom=(focus[2] or 0)-GROUND_DROP
      local top=precipDeckY or ((focus[2] or 0)+SNOW_CEIL*WP._cloudHeightScale())
      local o=WP._procVectors(WP._procScratch.snowProbe,ex,ey,ez,snow.lastWindX,snow.lastWindZ,1,1,1)
      o.focus=focus;o.nearRadius=1.5;o.farRadius=SNOW_STREAM_RADIUS;o.topY=top;o.bottomY=bottom
      o.span=precipDeckSpan or SNOW_CEIL_SPAN;o.time=snowTime;o.paused=WP._animationPaused;o.intensity=snow.lastIntensity or 0;o.ball=false
      -- 8.2.13: TSNOW now uses the same anti-fuzz population principle as
      -- ordinary snow/blizzard, but with a deliberately larger fully-dense
      -- local core and a denser detailed-card shell. The old uniform TSNOW
      -- field spent most of its MAX population on sub-pixel horizon points,
      -- reading as white fuzz while the space above the player felt empty.
      local snowWx=tostring(wxId or V.weatherFxId or ''):upper()
      local tsnow=(snowWx=='THUNDERSNOW' or snowWx=='TSNOW')
      o.radialTaper=(snowWx=='SNOW_LIGHT' or snowWx=='SNOW' or snowWx=='BLIZZARD' or tsnow)
      if tsnow then
        -- Keep the complete render-distance contract, but make the visible
        -- storm local: 100% population through the overhead core, then a very
        -- steep deterministic falloff. More detailed flakes are submitted in
        -- the near shell so looking up reads as blowing snow, not a point fog.
        o.coreRadius,o.edgeKeep,o.taperPower=.16,.00000025,17
        o.detailRadius,o.detailDensityBoost,o.detailExtraCap=110,1.80,4096
      elseif snowWx=='BLIZZARD' then
        o.coreRadius,o.edgeKeep,o.taperPower=.08,.0000005,16
      else
        o.coreRadius,o.edgeKeep,o.taperPower=.10,.000001,14
      end
      o.uniformField=WP._uniformPrecipField==true
      local ok,v=V.safeCall(PS.probe,Voxel3D,o)
      if ok and v==true then
        fullGPU=true
        snow.gpuFullVisual=true
        snow.gpuActive=logicalActive
        local qb=qualityBudget()
        local face=(lastEye~=nil) and firstPerson()
        local probeTarget=1
        if face then
          probeTarget=min(16,max(4,floor((tonumber(qb.snowProbeCap) or 96)/6+0.5)))
        end
        snow.simActive=min(logicalActive,probeTarget)
        active=snow.simActive
      end
    end
  end
  -- Preferred MAX path: one compact row per simulated flake. A failed or
  -- unsupported instancing probe falls through to the byte-proven CPU path.
  local nearHealthy=fullGPU
  local nearVerts=0
  -- 8.1.90: do not submit visible snow through the secondary near-field
  -- instancing backend. Several drivers can accept/validate instance attributes
  -- yet collapse their world positions into one narrow vertical column. Dense
  -- snow is still GPU-virtualized by the separately proven ProceduralSnowField;
  -- when that backend is unavailable or the population is small, explicit CPU
  -- cards carry real world XYZ per vertex and cannot collapse into a fountain.
  -- This changes submission ownership only, not flake count/size/motion.
  local buf = snowBuf
  if not nearHealthy then buf:reset() end

  local ax, ay, az = snow.x, snow.y, snow.z
  local asize, aa, alife, amax = snow.size, snow.a, snow.life, snow.maxLife
  local arot, abr = snow.rot, snow.br
  local DEPTH = SNOW_DRAW_RADIUS * 1.15
  local CULL2 = SNOW_DRAW_RADIUS * SNOW_DRAW_RADIUS

  if not nearHealthy then
  for i = 1, active do
    local x, y, z = ax[i], ay[i], az[i]
    local tx, ty, tz = ex - x, ey - y, ez - z
    local t2 = tx * tx + ty * ty + tz * tz
    -- Do not infer visibility from Voxel3D.focus here. On several voxel hosts
    -- focus is the player/world anchor, not the camera view ray; using it as a
    -- forward vector culled the entire snow field. Keep the proven distance-only
    -- cull from the pre-4.33.1 renderer and let the GPU clip true rear geometry.
    if t2 < CULL2 and t2 > 1e-6 then
      local size = asize[i]
      local a = aa[i]
      local lifeT = alife[i] / max(0.05, amax[i])
      if lifeT < 0.08 then a = a * (lifeT / 0.08) end
      if lifeT > 0.90 then a = a * (1 - (lifeT - 0.90) / 0.10) end

      local tl = sqrt(t2)
      local near = 1.0 - min(1.0, tl / DEPTH)
      -- FPV depth: near flakes larger; far still visible for map-wide snow.
      size = size * (0.50 + near * 1.15)
      a = a * (0.30 + near * 0.70)

      if a > 0.012 then
        tx, ty, tz = tx / tl, ty / tl, tz / tl
        -- right = worldUp x toEye, up = toEye x right; then roll both axes by
        -- the tumble angle so flakes are not all stamped at one orientation.
        local rx, rz = -tz, tx
        local rl = sqrt(rx * rx + rz * rz)
        if rl < 1e-4 then rx, rz = 1, 0 else rx, rz = rx / rl, rz / rl end
        local ux = ty * rz
        local uy = tz * rx - tx * rz
        local uz = -ty * rx
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        if ul < 1e-4 then ux, uy, uz = 0, 1, 0 else ux, uy, uz = ux / ul, uy / ul, uz / ul end

        local ang = arot[i] or 0
        local ca, sa = fcos(ang), fsin(ang)
        local hs = size * 0.55
        local axx = (rx * ca + ux * sa) * hs
        local axy = (uy * sa) * hs
        local axz = (rz * ca + uz * sa) * hs
        local ayx = (ux * ca - rx * sa) * hs
        local ayy = (uy * ca) * hs
        local ayz = (uz * ca - rz * sa) * hs

        local br = abr[i] or 1

        local c1x, c1y, c1z = x - axx + ayx, y - axy + ayy, z - axz + ayz
        local c2x, c2y, c2z = x + axx + ayx, y + axy + ayy, z + axz + ayz
        local c3x, c3y, c3z = x + axx - ayx, y + axy - ayy, z + axz - ayz
        local c4x, c4y, c4z = x - axx - ayx, y - axy - ayy, z - axz - ayz

        buf:push(c1x, c1y, c1z, br, 0, 0, a)
        buf:push(c2x, c2y, c2z, br, 1, 0, a)
        buf:push(c3x, c3y, c3z, br, 1, 1, a)
        buf:push(c1x, c1y, c1z, br, 0, 0, a)
        buf:push(c3x, c3y, c3z, br, 1, 1, a)
        buf:push(c4x, c4y, c4z, br, 0, 1, a)
      end
    end
  end

  -- A fully rear/distance-culled near shell is still a healthy 3D frame.
  if buf.n < 3 then
    nearHealthy=true
  else
    snowMesh = uploadMesh(snowMesh, SNOW_FMT, buf)
    if snowMesh then
      local snowSh = getSnowShader() or getCardFallbackShader() or getRainShader()
      if snowSh then
        beginPass(Voxel3D, snowSh)
        local tr,tg,tb=celestialTint("snow",1,1,1)
        V.safeCall(love.graphics.setColor,tr,tg,tb,1)
        local okDraw = V.safeCall(love.graphics.draw, snowMesh)
        endPass(Voxel3D)
        if okDraw then nearVerts=buf.n;nearHealthy=true end
      end
    end
  end
  end -- legacy CPU near renderer

  -- 8.2.2 probing happens before any legacy visible CPU mesh work above.

  -- Zero-upload procedural far field. Only visual distance flakes are virtual;
  -- collision / face-contact / landing particles remain in the near shell.
  local farCount=fullGPU and logicalActive or (snow.gpuActive or 0)
  local farHealthy=true
  local farDrawn=0
  if farCount>0 then
    local PS=WP._proceduralSnowModule()
    if not (PS and PS.draw) then
      farHealthy=false
    else
      local tr,tg,tb=celestialTint("snow",1,1,1)
      local focus=lastStreamFocus or WP._procScratch.zero3
      local bottom=(focus[2] or 0)-GROUND_DROP
      local top=precipDeckY or ((focus[2] or 0)+SNOW_CEIL*WP._cloudHeightScale())
      -- Legacy source gate / semantic marker: PS.draw uses wind={snow.lastWindX or 0,snow.lastWindZ or 0}
      local o=WP._procVectors(WP._procScratch.snowDraw,ex,ey,ez,snow.lastWindX,snow.lastWindZ,tr,tg,tb)
      o.count=farCount;o.focus=focus;o.nearRadius=fullGPU and 1.5 or max(SNOW_MIN_R,snow.simRadius or 128);o.farRadius=SNOW_STREAM_RADIUS
      o.topY=top;o.bottomY=bottom;o.span=precipDeckSpan or SNOW_CEIL_SPAN;o.time=snowTime;o.paused=WP._animationPaused;o.intensity=snow.lastIntensity or 0
      local S=settingsModule();o.ball=S and S.snowShape and S.snowShape()=="ball" or false
      local snowWx=tostring(wxId or V.weatherFxId or ''):upper()
      local tsnow=(snowWx=='THUNDERSNOW' or snowWx=='TSNOW')
      o.radialTaper=(snowWx=='SNOW_LIGHT' or snowWx=='SNOW' or snowWx=='BLIZZARD' or tsnow)
      if tsnow then
        o.coreRadius,o.edgeKeep,o.taperPower=.16,.00000025,17
        o.detailRadius,o.detailDensityBoost,o.detailExtraCap=110,1.80,4096
      elseif snowWx=='BLIZZARD' then
        o.coreRadius,o.edgeKeep,o.taperPower=.08,.0000005,16
      else
        o.coreRadius,o.edgeKeep,o.taperPower=.10,.000001,14
      end
      o.uniformField=WP._uniformPrecipField==true
      local ok,healthy,count=V.safeCall(PS.draw,Voxel3D,o)
      farHealthy=ok and healthy==true and (tonumber(count) or 0)==farCount
      farDrawn=tonumber(count) or 0
    end
  end
  drawnSnowVerts=nearVerts+farDrawn*4
  drawnSnowHealthy=nearHealthy and farHealthy
end

-- ---------------------------------------------------------------------------
-- DRAW: FACE SPECKS
-- ---------------------------------------------------------------------------
-- Only reachable when a simulated flake actually intersected the eye sphere.
-- The quad is world geometry pinned a fraction of a unit off the eye along the
-- direction the flake arrived from, so it turns with the head like something
-- stuck to you rather than sliding like a screen decal. It swells slightly and
-- fades: melt, not wipe.
local function drawFaceSpecks(Voxel3D)
  local active = face.active or 0
  if active <= 0 or not (Voxel3D and Voxel3D.vp) then return end
  local eye = Voxel3D.eye
  if not eye then return end
  local ex, ey, ez = eye[1] or 0, eye[2] or 0, eye[3] or 0
  local buf = faceBuf
  buf:reset()

  for i = 1, active do
    local age = face.age[i] or 99
    if age < FACE_LIFE then
      local t = age / FACE_LIFE
      local a = (1 - t * t) * 0.55
      if t < 0.10 then a = a * (t / 0.10) end
      if a > 0.02 then
        local dx, dy, dz = face.dx[i], face.dy[i], face.dz[i]
        -- Melt: spreads a little and slides a touch downward as it goes.
        local hs = face.size[i] * (1.0 + t * 0.55)
        local x = ex + dx * FACE_DIST
        local y = ey + dy * FACE_DIST - t * face.size[i] * 0.8
        local z = ez + dz * FACE_DIST
        -- Billboard against the arrival direction.
        local rx, rz = -dz, dx
        local rl = sqrt(rx * rx + rz * rz)
        if rl < 1e-4 then rx, rz = 1, 0 else rx, rz = rx / rl, rz / rl end
        local ux = dy * rz
        local uy = dz * rx - dx * rz
        local uz = -dy * rx
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        if ul < 1e-4 then ux, uy, uz = 0, 1, 0 else ux, uy, uz = ux / ul, uy / ul, uz / ul end
        local c1x, c1y, c1z = x - rx * hs + ux * hs, y + uy * hs, z - rz * hs + uz * hs
        local c2x, c2y, c2z = x + rx * hs + ux * hs, y + uy * hs, z + rz * hs + uz * hs
        local c3x, c3y, c3z = x + rx * hs - ux * hs, y - uy * hs, z + rz * hs - uz * hs
        local c4x, c4y, c4z = x - rx * hs - ux * hs, y - uy * hs, z - rz * hs - uz * hs
        buf:push(c1x, c1y, c1z, 1, 0, 0, a)
        buf:push(c2x, c2y, c2z, 1, 1, 0, a)
        buf:push(c3x, c3y, c3z, 1, 1, 1, a)
        buf:push(c1x, c1y, c1z, 1, 0, 0, a)
        buf:push(c3x, c3y, c3z, 1, 1, 1, a)
        buf:push(c4x, c4y, c4z, 1, 0, 1, a)
      end
    end
  end

  faceMesh = uploadMesh(faceMesh, SNOW_FMT, buf)
  if not faceMesh then return end
  beginPass(Voxel3D, getSnowShader())
  V.safeCall(love.graphics.setColor, 1, 1, 1, 1)
  V.safeCall(love.graphics.draw, faceMesh)
  endPass(Voxel3D)
end

-- ---------------------------------------------------------------------------
-- DRAW: GROUND LAYERS
-- ---------------------------------------------------------------------------
-- Ground impacts. These are SPLASHES, not stains: a drop hits, throws a short
-- expanding ring, and it is gone in a fraction of a second. Rain that lands
-- without doing anything is the single biggest tell that a rain effect is just
-- streaks drawn over a scene.
--
-- REGRESSION FIXED HERE: 4.28.72 gave the rain shader UVs in .g/.b so streaks
-- could taper, but left this function pushing (a, a, a, a) -- the old layout,
-- where every channel was alpha. So wet marks were being shaded on garbage UVs:
-- the "across" and "along" falloffs were both reading the alpha value. They
-- carry real UVs now and use the soft radial shader, which is what they wanted
-- in the first place.
local function drawWetMarks(Voxel3D)
  if not splashesEnabled() then return end
  local active = wet.active or 0
  if active <= 0 or not (Voxel3D and Voxel3D.vp) then return end
  local buf = wetBuf
  buf:reset()
  for i = 1, active do
    local age = wet.age[i] or 99
    local life = wet.life[i] or WET_LIFE
    if age < life then
      local t = age / life
      -- Splash profile: snaps to full size fast, then fades. A ring that
      -- expands while it dies reads as an impact; one that just fades reads as
      -- a stain appearing out of nowhere.
      local grow = 1.0 - (1.0 - t) * (1.0 - t)      -- ease-out
      local a = wet.a[i] * (1.0 - t) * (1.0 - t)
      if t < 0.06 then a = a * (t / 0.06) end
      if a > 0.02 then
        local x, y, z = wet.x[i], wet.y[i], wet.z[i]
        local style=wet.style[i] or 1
        local shape=(style==4 and 1.30) or (style==2 and .66) or (style==5 and 1.05) or 1
        local r = wet.size[i] * shape * (0.35 + grow * 1.5)
        if style==2 then a=a*.66 elseif style==3 then a=min(1,a*1.10) elseif style==4 then a=a*.88 end
        buf:push(x - r, y, z - r, 1, 0, 0, a)
        buf:push(x + r, y, z - r, 1, 1, 0, a)
        buf:push(x + r, y, z + r, 1, 1, 1, a)
        buf:push(x - r, y, z - r, 1, 0, 0, a)
        buf:push(x + r, y, z + r, 1, 1, 1, a)
        buf:push(x - r, y, z + r, 1, 0, 1, a)
      end
    end
  end
  wetMesh = uploadMesh(wetMesh, SNOW_FMT, buf)
  if not wetMesh then return end
  beginPass(Voxel3D, getSnowShader())
  -- Pale, slightly cool: a splash catches light, it is not a dark stain.
  V.safeCall(love.graphics.setColor, 0.62, 0.70, 0.82, 1)
  V.safeCall(love.graphics.draw, wetMesh)
  V.safeCall(love.graphics.setColor, 1, 1, 1, 1)
  endPass(Voxel3D)
end


-- Ground snow uses the grain shader, not the rain shader: the rain shader
-- hardcodes a blue-grey pixel colour and would have painted every drift the
-- colour of a puddle. The grain shader passes the per-vertex tint through.
-- Ground snow drew as HARD-EDGED WHITE PARALLELOGRAMS. Caught by rendering the
-- real vertex stream with the historical offline rasterizer and looking at it -- no
-- simulation test could see it, because the simulation was correct: the right
-- number of patches in the right places, drawn as opaque rectangles.
--
-- Cause: it used the grain shader, which passes the vertex tint straight
-- through with no falloff, so every patch was a flat quad with a hard border
-- and alpha up to 0.9. Scattered over the ground that reads as paper confetti,
-- which is exactly the "cheap 2D overlay" look this whole rework exists to get
-- rid of.
--
-- Now it carries quad UVs and uses the snow shader's soft radial falloff, so
-- patches have no visible edge and blend into each other into a continuous
-- sheet. Peak alpha is lowered too: snow lying on ground is a tint on the
-- terrain, not a white decal hiding it.
local BankGeom = {
  cx={1.0,0.70710678,0.0,-0.70710678,-1.0,-0.70710678,0.0,0.70710678},
  cz={0.0,0.70710678,1.0,0.70710678,0.0,-0.70710678,-1.0,-0.70710678},
}

function BankGeom.tri(buf,x1,y1,z1,x2,y2,z2,x3,y3,z3,r,g,b,a)
  buf:push(x1,y1,z1,r,g,b,a); buf:push(x2,y2,z2,r,g,b,a); buf:push(x3,y3,z3,r,g,b,a)
end

function BankGeom.quad(buf,x1,y1,z1,x2,y2,z2,x3,y3,z3,x4,y4,z4,r,g,b,a)
  BankGeom.tri(buf,x1,y1,z1,x2,y2,z2,x3,y3,z3,r,g,b,a)
  BankGeom.tri(buf,x1,y1,z1,x3,y3,z3,x4,y4,z4,r,g,b,a)
end

-- Full/rectangular support: a flat interior bank with a sloped perimeter. The
-- outer ring lands exactly on the neighbouring snow top (or this object's bare
-- support height), so snow joins continuously across covered ground but tapers
-- off at roofs, walls, shorelines and other exposed edges instead of hanging.
function BankGeom.rect(buf,x,z,baseY,topY,eW,eE,eN,eS,halfX,halfZ,amt)
  local h=max(0,topY-baseY)
  if h<=0.001 then return end
  local bevel=min(2.0,max(0.55,h*0.58))
  local ix, iz=max(0.25,halfX-bevel), max(0.25,halfZ-bevel)
  local topA=min(0.99,0.72+amt*0.27)
  local tr,tg,tb=0.94,0.97,1.00
  local sr,sg,sb=0.78,0.86,0.96
  -- Interior top.
  BankGeom.quad(buf,x-ix,topY,z-iz,x+ix,topY,z-iz,x+ix,topY,z+iz,x-ix,topY,z+iz,tr,tg,tb,topA)
  -- Four side ramps.
  BankGeom.quad(buf,x-ix,topY,z-iz,x+ix,topY,z-iz,x+ix,eN,z-halfZ,x-ix,eN,z-halfZ,sr,sg,sb,topA)
  BankGeom.quad(buf,x+ix,topY,z-iz,x+ix,topY,z+iz,x+halfX,eE,z+iz,x+halfX,eE,z-iz,sr,sg,sb,topA)
  BankGeom.quad(buf,x+ix,topY,z+iz,x-ix,topY,z+iz,x-ix,eS,z+halfZ,x+ix,eS,z+halfZ,sr,sg,sb,topA)
  BankGeom.quad(buf,x-ix,topY,z+iz,x-ix,topY,z-iz,x-halfX,eW,z-iz,x-halfX,eW,z+iz,sr,sg,sb,topA)
  -- Corner wedges close the bevel without extending beyond the supporting cell.
  local nw, ne, se, sw=min(eN,eW), min(eN,eE), min(eS,eE), min(eS,eW)
  BankGeom.quad(buf,x-ix,topY,z-iz,x-ix,eN,z-halfZ,x-halfX,nw,z-halfZ,x-halfX,eW,z-iz,sr,sg,sb,topA)
  BankGeom.quad(buf,x+ix,topY,z-iz,x+halfX,eE,z-iz,x+halfX,ne,z-halfZ,x+ix,eN,z-halfZ,sr,sg,sb,topA)
  BankGeom.quad(buf,x+ix,topY,z+iz,x+ix,eS,z+halfZ,x+halfX,se,z+halfZ,x+halfX,eE,z+iz,sr,sg,sb,topA)
  BankGeom.quad(buf,x-ix,topY,z+iz,x-halfX,eW,z+iz,x-halfX,sw,z+halfZ,x-ix,eS,z+halfZ,sr,sg,sb,topA)
end

-- Tree/canopy tops get a rounded cap. The outer ring returns to the actual
-- supporting surface, so the white snow follows the crown rather than forming
-- a square cell-sized plate around the tree.
function BankGeom.round(buf,x,z,baseY,topY,radius,amt)
  local h=max(0,topY-baseY); if h<=0.001 then return end
  local bevel=min(1.6,max(0.45,h*0.55)); local inner=max(0.35,radius-bevel)
  local edgeY=baseY+min(0.12,h*0.08)
  local topA=min(0.99,0.74+amt*0.25)
  local tr,tg,tb=0.95,0.98,1.00; local sr,sg,sb=0.80,0.88,0.97
  for k=1,8 do
    local j=(k%8)+1
    local ix1=x+BankGeom.cx[k]*inner; local iz1=z+BankGeom.cz[k]*inner
    local ix2=x+BankGeom.cx[j]*inner; local iz2=z+BankGeom.cz[j]*inner
    local ox1=x+BankGeom.cx[k]*radius; local oz1=z+BankGeom.cz[k]*radius
    local ox2=x+BankGeom.cx[j]*radius; local oz2=z+BankGeom.cz[j]*radius
    BankGeom.tri(buf,x,topY,z,ix1,topY,iz1,ix2,topY,iz2,tr,tg,tb,topA)
    BankGeom.quad(buf,ix1,topY,iz1,ox1,edgeY,oz1,ox2,edgeY,oz2,ix2,topY,iz2,sr,sg,sb,topA)
  end
end


-- 4.35.27 sub-cell mound: every deposited flake contributes to a rounded
-- world-space patch. Eight independently clipped radii let a mound cross a
-- normal tile seam but stop exactly at water/object/support boundaries. This
-- eliminates the old one-square-per-cell blanket without adding draw calls.
function BankGeom.patch(buf,x,z,baseY,topY,amt,radii)
  local h=max(0,topY-baseY); if h<=0.001 then return end
  local topA=min(0.99,0.70+amt*0.29)
  local cr,cg,cb=0.96,0.985,1.00
  local er,eg,eb=0.82,0.90,0.98
  -- 8.1.68: broad, almost-level interior with one soft perimeter slope.
  -- Coalesced banks should read as settled drifts, not overlapping domes.
  local innerY=topY-max(0.010,h*0.012)
  local edgeY=baseY+min(h*0.22,0.34)
  for k=1,8 do
    local j=(k%8)+1
    local r1=max(0.20,radii[k] or 1.0); local r2=max(0.20,radii[j] or 1.0)
    local i1=r1*0.72; local i2=r2*0.72
    local ix1=x+BankGeom.cx[k]*i1; local iz1=z+BankGeom.cz[k]*i1
    local ix2=x+BankGeom.cx[j]*i2; local iz2=z+BankGeom.cz[j]*i2
    local ox1=x+BankGeom.cx[k]*r1; local oz1=z+BankGeom.cz[k]*r1
    local ox2=x+BankGeom.cx[j]*r2; local oz2=z+BankGeom.cz[j]*r2
    BankGeom.tri(buf,x,topY,z,ix1,innerY,iz1,ix2,innerY,iz2,cr,cg,cb,topA)
    BankGeom.quad(buf,ix1,innerY,iz1,ox1,edgeY,oz1,ox2,edgeY,oz2,ix2,innerY,iz2,er,eg,eb,topA)
  end
end

local function drawGroundSnow(Voxel3D)
  local active=gsnow.active or 0
  if active<=0 or not (Voxel3D and Voxel3D.vp) then return end
  local revision=tonumber(WP._gsnowPoolRevision) or 0
  -- 8.2.3: bank vertices are rebuilt/uploaded only when the staged SnowPack
  -- snapshot changes. Previously this repeated identical Lua geometry and GPU
  -- uploads every rendered frame, a major snow-only CPU cost on phones.
  if not gsnowMesh or WP._gsnowMeshRevision~=revision then
    local buf=gsnowBuf; buf:reset()
    local radii=BankGeom._radii or {}; BankGeom._radii=radii
    local SSP=WP._snowSurfacePaintModule()
    for i=1,active do
      local amt=gsnow.amount[i] or 0
      local h=gsnow.height[i] or 0
      local kind=gsnow.kind[i] or "ground"
      local physical=(SSP and SSP.usePhysicalBank) and SSP.usePhysicalBank(kind,gsnow.class[i],gsnow.profile[i]) or (kind=="ground" or kind=="grass" or kind=="ice")
      if physical and amt>0.012 and h>0.015 then
        radii[1],radii[2],radii[3],radii[4]=gsnow.r1[i],gsnow.r2[i],gsnow.r3[i],gsnow.r4[i]
        radii[5],radii[6],radii[7],radii[8]=gsnow.r5[i],gsnow.r6[i],gsnow.r7[i],gsnow.r8[i]
        BankGeom.patch(buf,gsnow.x[i],gsnow.z[i],gsnow.baseY[i] or 0,gsnow.y[i] or 0,amt,radii)
      end
    end
    gsnowMesh=uploadMesh(gsnowMesh,SNOW_FMT,buf)
    WP._gsnowMeshRevision=revision
  end
  if not gsnowMesh then return end
  beginPass(Voxel3D,getGrainShader())
  V.safeCall(love.graphics.setColor,1,1,1,1)
  V.safeCall(love.graphics.draw,gsnowMesh)
  endPass(Voxel3D)
end

-- `only` selects a colour subset. Ash alternates black and grey PER PARTICLE
-- (keyed off spin), but the soft falloff needs the vertex rgb channels for UVs,
-- so colour is now a per-pass uniform -- and one pass cannot carry two colours.
-- Rather than approximate (which would have quietly turned all ash one shade),
-- ash is drawn as two passes and each keeps its exact tint. Every other family
-- is single-coloured and draws in one pass as before.
local function drawFootprints(Voxel3D)
  local active=foot.active or 0
  if active<=0 or not (Voxel3D and Voxel3D.vp) then return end
  local buf=gsnowBuf
  buf:reset()
  for i=1,active do
    local a=foot.a[i] or 0
    if a>0.02 then
      local x,y,z=foot.x[i],foot.y[i],foot.z[i]
      local ang=foot.angle[i] or 0
      local fx,fz=cos(ang),sin(ang)
      local rx,rz=-fz,fx
      local depression=foot.depression[i] or 0
      local hw=(1.30+min(0.18,depression*0.20))*(foot.size[i] or 1)
      local hl=(2.50+min(0.25,depression*0.28))*(foot.size[i] or 1)
      local x1,z1=x-rx*hw-fx*hl,z-rz*hw-fz*hl
      local x2,z2=x+rx*hw-fx*hl,z+rz*hw-fz*hl
      local x3,z3=x+rx*hw+fx*hl,z+rz*hw+fz*hl
      local x4,z4=x-rx*hw+fx*hl,z-rz*hw+fz*hl
      buf:push(x1,y,z1,1,0,0,a)
      buf:push(x2,y,z2,1,1,0,a)
      buf:push(x3,y,z3,1,1,1,a)
      buf:push(x1,y,z1,1,0,0,a)
      buf:push(x3,y,z3,1,1,1,a)
      buf:push(x4,y,z4,1,0,1,a)
    end
  end
  footMesh=uploadMesh(footMesh,SNOW_FMT,buf)
  if not footMesh then return end
  beginPass(Voxel3D,getSnowShader())
  V.safeCall(love.graphics.setColor,0.22,0.28,0.36,0.82)
  V.safeCall(love.graphics.draw,footMesh)
  V.safeCall(love.graphics.setColor,1,1,1,1)
  endPass(Voxel3D)
end

local function drawGrainPass(Voxel3D, wantedKind, only, firstIdx, lastIdx, ex, ey, ez)
  local active = grain.active or 0
  if active <= 0 or not (Voxel3D and Voxel3D.vp) then return 0, false end
  firstIdx = firstIdx or 1
  lastIdx = lastIdx or active
  if firstIdx > lastIdx then return 0, true end
  if ex == nil then
    local eye = Voxel3D.eye
    ex, ey, ez = eye and (eye[1] or 0) or 0, eye and (eye[2] or 0) or 0, eye and (eye[3] or 0) or 0
  end
  local buf = grainBuf
  buf:reset()
  -- Tint is selected once per family pass.  The old path looked up LEAF COLOR
  -- once per leaf, every frame, then used the *last processed particle* as the
  -- colour for the entire mesh.  Besides wasting protected Settings lookups,
  -- particle recycling could make the whole field pulse between shades.
  local passKind = wantedKind or grain.kind[1]
  local grainR, grainG, grainB = 0.85, 0.72, 0.48
  if passKind == 1 then
    grainR, grainG, grainB = 0.90, 0.95, 1.00 -- hail: ice
  elseif passKind == 2 then
    grainR, grainG, grainB = 0.85, 0.72, 0.48 -- stable sand/tan pass
  elseif passKind == 3 then
    local leaf = "green"
    local S = settingsModule()
    if S and S.leafColor then leaf = S.leafColor() or "green" end
    if leaf == "yellow" then
      grainR, grainG, grainB = 0.78, 0.68, 0.18
    elseif leaf == "orange" then
      grainR, grainG, grainB = 0.82, 0.42, 0.14
    elseif leaf == "brown" then
      grainR, grainG, grainB = 0.48, 0.30, 0.14
    else
      grainR, grainG, grainB = 0.30, 0.58, 0.22
    end
  elseif passKind == 4 then
    if only == "dark" then
      grainR, grainG, grainB = 0.10, 0.10, 0.11
    else
      grainR, grainG, grainB = 0.62, 0.62, 0.60
    end
  end
  local DEPTH = STREAM_RADIUS * 1.15
  -- Sand presentation is CAMERA-PITCH INVARIANT. A previous workaround scaled
  -- and lifted sand whenever the view tilted down, and even switched to an
  -- always-pass depth mode at steep pitch. That made a subtle world-space grit
  -- field suddenly become large opaque cards simply by looking at the ground.
  -- Camera orientation may decide what is visible; it must never change a sand
  -- particle's world-space size, alpha, clearance or occlusion behavior.
  for i = firstIdx, lastIdx do
    local kind = grain.kind[i]
    local dark = (grain.spin[i] or 0) >= 0.5
    local skip = (wantedKind ~= nil and kind ~= wantedKind)
    if only == "dark" and not dark then skip = true end
    if only == "light" and dark then skip = true end
    if not skip then
    local x, y, z = grain.x[i], grain.y[i], grain.z[i]
    local size, a = grain.size[i], grain.a[i]
    local settledLeaf = kind == 3 and grain.leafSettled[i] == true
    local lifeT
    if settledLeaf then
      -- Piles have their own long visible lifetime. Do NOT fade them according
      -- to the original airborne timer (the 4.35.21 path could leave a leaf
      -- physically settled but fully transparent after its flight maxLife).
      lifeT = (grain.leafSettleT[i] or 0) / max(0.05, grain.leafSettleLife[i] or 35)
      if lifeT > 0.90 then a = a * max(0, 1 - (lifeT - 0.90) / 0.10) end
    else
      lifeT = grain.life[i] / max(0.05, grain.maxLife[i])
      if lifeT < 0.08 then a = a * (lifeT / 0.08) end
      if lifeT > 0.92 then a = a * max(0, 1 - (lifeT - 0.92) / 0.08) end
    end
    -- Small fixed lift keeps ground grit from z-fighting with the floor mesh.
    -- It is intentionally independent of camera pitch; changing it while
    -- looking down was one cause of the apparent "voxel angle" pop.
    if kind == 2 then
      y = y + 0.25
    end
    local tx, ty, tz = ex - x, ey - y, ez - z
    local t2 = tx * tx + ty * ty + tz * tz
    -- Same host rule as snow: never use focus-as-forward for grains. Sand, hail,
    -- leaves and ash must remain visible regardless of whether a host exposes
    -- focus as a camera target or a player/world anchor.
    if t2 > 1e-6 then
      local tl = sqrt(t2)
      -- Sand/dust: horizontal distance so elevated cameras do not fade the field.
      local near
      if kind == 2 then
        local horiz = sqrt(tx * tx + tz * tz)
        near = 1.0 - min(1.0, horiz / DEPTH)
        if near < 0.30 then near = 0.30 end
      else
        near = 1.0 - min(1.0, tl / DEPTH)
      end
      size = size * (0.40 + near * 1.35)
      if kind == 2 then
        a = a * (0.60 + near * 0.45)
      else
        a = a * (0.35 + near * 0.65)
      end
      if tl < 3.0 then a = a * (tl / 3.0) end
      local hs = size * 0.5
      -- Family tint is chosen once above; shape/brightness still varies per
      -- particle through the vertex data and family shader.
      -- Grains were the LAST precipitation family still drawing as hard flat
      -- quads. Snow got a soft radial falloff in 4.28.71, ground snow and rain
      -- in 4.28.72-73; this one was missed, so sand and dust rendered as brown
      -- squares sliding across the screen in first person.
      --
      -- Two things were wrong and both had to change:
      --   * the grain shader passes the vertex tint straight through with no
      --     falloff, so a quad was a rectangle with a hard border;
      --   * the quad was axis-aligned with rotation hardcoded to 0, so every
      --     grain was the same upright square -- no tumble at all, even though
      --     spin is simulated per particle.
      --
      -- Sand is now elongated ALONG its travel and rolled by its own spin, and
      -- the shader reads quad UVs out of an unused channel to soften the edge.
      -- The tint has to move to make room: rgb no longer travels per-vertex, so
      -- the colour is sent once via setColor for the whole pass instead.
      -- Hail does not tumble the way a leaf or a snowflake does -- it is a
      -- dense lump falling ballistically. Give it a fixed slight tilt instead
      -- of the spin-driven roll, so a hail field does not shimmer.
      local rot
      if kind == 1 then
        -- Near-parallel. seed*0.6 spread the streaks over ~34 degrees, so a
        -- hail field looked like it was falling in several directions at once.
        -- Real hail comes down on one line, leaned by the wind; the small
        -- residual spread is per-stone jitter, not independent headings.
        rot = 0.10 + (grain.seed[i] or 0) * 0.10
      elseif kind == 4 then
        -- Ash plates tumble and flutter while falling.
        rot = ((grain.spin[i] or 0) * PI2) + simTime * (1.4 + (grain.seed[i] or 0) * 3.6)
      elseif kind == 3 then
        if grain.leafSettled[i] then
          -- Pile leaves stop tumbling. Keep one stable varied angle so a pile
          -- reads as overlapping individual leaves rather than spinning cards.
          rot = (grain.spin[i] or 0) * PI2
        else
          -- Leaves tumble and flutter as they blow past
          local seed=grain.seed[i] or 0
          local flutter = fsin(simTime * (4.0 + seed * 3.0) + seed * 9.0) * 0.55
          rot = ((grain.spin[i] or 0) * PI2) + simTime * (2.8 + (grain.spin[i] or 0.5) * 5.5) + flutter
        end
      else
        rot = ((grain.spin[i] or 0) * PI2) + simTime * (0.6 + (grain.seed[i] or 0) * 2.2)
      end
      local ca2, sa2 = fcos(rot), fsin(rot)
      -- Same camera-facing billboard path for every angle (proven at 75/3rd/1st).
      local hw = hs * ((kind == 1) and 1.02 or 0.62)
      if kind == 1 then
        -- Hail is a pellet, not a streak. The old 2.2x card aspect ratio made
        -- distant stones line up as artificial white rails in the background.
        hs = hs * 0.98
      elseif kind == 2 then
        local s = grain.seed[i] or 0.5
        local speed = grain.hSpeed[i] or sqrt((grain.vx[i] or 0)^2 + (grain.vz[i] or 0)^2)
        local streak = 1.15 + min(2.4, speed * 0.028)
        if s > 0.72 then
          hs = hs * (0.70 + s * 0.25)
          hw = hs * (0.55 + s * 0.20)
        else
          hs = hs * (0.55 + s * 0.20)
          hw = hs * streak
        end
        -- Fixed world-space cap. Camera pitch must never change sand size.
        if hs > 0.85 then hs = 0.85 end
        if hw > 1.6 then hw = 1.6 end
      elseif kind == 3 then
        -- A leaf is a BLADE, not a sliver. At 0.32-0.60 of its length the
        -- silhouette had no room to read as anything but a streak, which is
        -- part of why leaves looked like coloured marks. Real leaves run
        -- roughly 0.45-0.75 as wide as they are long; the shader carves the
        -- ovate outline inside that, so the quad has to be wide enough to hold
        -- one.
        -- SEED COMPOUNDED THREE TIMES. It scales leafScale at spawn
        -- (0.45 + s*1.15), again here (1.15 + s*0.85), and again in the width
        -- (0.52 + s*0.26). A seed-1.0 leaf came out SIX times the length of a
        -- seed-0.0 one -- 3.78 world units against 0.61 -- and it is those
        -- outliers that read as fans crossing the screen rather than leaves.
        --
        -- The spawn scale already provides the small-to-large mix, so this term
        -- is flattened to a near-constant. The variety is kept; the giants are
        -- not.
        local s = grain.seed[i] or 0.5
        hs = hs * (1.15 + s * 0.25)
        hw = hs * (0.52 + s * 0.26)
        if grain.leafSettled[i] then
          hs = hs * 0.62
          hw = hw * 1.28
        end
      elseif kind == 4 then
        local seedA = grain.seed[i] or 0.5
        if seedA < 0.333 then
          hs = hs * (0.95 + seedA * 0.35)
          hw = hs * (0.80 + seedA * 0.35)
        elseif seedA < 0.666 then
          hs = hs * (1.35 + seedA * 0.45)
          hw = hs * (0.28 + (seedA - 0.333) * 0.25)
        else
          hs = hs * (0.75 + (seedA - 0.666) * 0.40)
          hw = hs * (0.70 + (seedA - 0.666) * 0.45)
        end
      end
      local invTl = 1.0 / tl
      local tnx, tny, tnz = tx * invTl, ty * invTl, tz * invTl
      local rx, rz = -tnz, tnx
      local rl = sqrt(rx * rx + rz * rz)
      if rl < 1e-4 then rx, rz = 1, 0 else rx, rz = rx / rl, rz / rl end
      local ux = tny * rz
      local uy = tnz * rx - tnx * rz
      local uz = -tny * rx
      local ul = sqrt(ux * ux + uy * uy + uz * uz)
      if ul < 1e-4 then ux, uy, uz = 0, 1, 0 else ux, uy, uz = ux / ul, uy / ul, uz / ul end

      local axx = (rx * ca2 + ux * sa2) * hs
      local axy = (uy * sa2) * hs
      local axz = (rz * ca2 + uz * sa2) * hs
      local ayx = (ux * ca2 - rx * sa2) * hw
      local ayy = (uy * ca2) * hw
      local ayz = (uz * ca2 - rz * sa2) * hw

      local q1x, q1y, q1z = x - axx + ayx, y - axy + ayy, z - axz + ayz
      local q2x, q2y, q2z = x + axx + ayx, y + axy + ayy, z + axz + ayz
      local q3x, q3y, q3z = x + axx - ayx, y + axy - ayy, z + axz - ayz
      local q4x, q4y, q4z = x - axx - ayx, y - axy - ayy, z - axz - ayz

      -- .r carries brightness, .g/.b the quad UV, .a the alpha.
      --
      -- UV INSET CONTROLS EDGE HARDNESS. The shared shader fades on
      -- d = dot(uv*2-1, uv*2-1), so mapping the quad corners to the full 0..1
      -- range gives a soft round blob -- correct for a snowflake, wrong for a
      -- hailstone. Insetting the corners keeps d small everywhere, so the
      -- falloff never reaches its soft tail and the stone reads as a hard
      -- bright pellet with a tight edge. No second shader needed.
      --
      -- This is what separates hail from snow visually: same white, completely
      -- different edge. Snow is a soft tumbling smudge; hail is a small hard
      -- dot falling fast and straight.
      local u0, u1 = 0, 1
      -- Inset 0.22/0.78 was TOO FAR. The shared shader fades on
      -- d = dot(uv*2-1, uv*2-1) and reaches zero only at d >= 1; that inset
      -- caps d at 0.63, so the corners never faded and every hailstone drew as
      -- a hard white SQUARE. Same defect the brown sand squares had, in a new
      -- colour, and introduced while trying to make hail look harder.
      --
      -- 0.05/0.95 still tightens the core relative to snow, but leaves d above
      -- 1 at the corners so they fade out completely and the stone is round.
      -- The rest of the hail read comes from size, opacity, fall speed and the
      -- absence of tumble -- not from the edge alone.
      -- INSETTING WAS THE WRONG DIRECTION. Inset keeps d small, so the falloff
      -- never completes -- 0.22/0.78 gave hard squares, and 0.05/0.95 gave a
      -- blob barely different from snow. EXPANDING the UVs past 0..1 does the
      -- opposite: d passes 1 well inside the quad, so the lit disc is a small
      -- tight core that fades to nothing before the corners. That is a bright
      -- pellet with a crisp edge and no square, which is exactly the read hail
      -- needs against snow's soft smudge.
      if kind == 1 then u0, u1 = -0.45, 1.45 end
      local br2 = 0.80 + (grain.seed[i] or 0) * 0.35
      if kind == 1 then br2 = 1.0 end   -- hail is bright ice, not dim grit
      -- Ash shader reads .r as the full 0..1 shape seed (3 silhouette bands).
      -- Do not compress it into the brightness range used by grit/hail.
      if kind == 4 then br2 = grain.seed[i] or 0.5 end
      buf:push(q1x, q1y, q1z, br2, u0, u0, a)
      buf:push(q2x, q2y, q2z, br2, u1, u0, a)
      buf:push(q3x, q3y, q3z, br2, u1, u1, a)
      buf:push(q1x, q1y, q1z, br2, u0, u0, a)
      buf:push(q3x, q3y, q3z, br2, u1, u1, a)
      buf:push(q4x, q4y, q4z, br2, u0, u1, a)
    end
    end
  end
  -- A requested family can legitimately have no visible cards after rear-camera
  -- culling. Treat that as healthy ownership, not a reason to draw a 2D overlay.
  if buf.n < 3 then return 0, true end
  grainMesh = uploadMesh(grainMesh, SNOW_FMT, buf)
  if not grainMesh then return 0, false end
  -- Per-family shader. Sand MUST NOT use the snowflake dendrite shader —
  -- pipeline audit: dendrite discards ~90% of quad pixels, so grit was
  -- effectively invisible at steep voxel angles (15/35/50) and weak elsewhere.
  local gKind = wantedKind or grain.kind[1]
  local gSh = getSnowShader() or getCardFallbackShader() or getRainShader()
  if gKind == 1 then
    gSh = getHailShader() or getCardFallbackShader() or getRainShader()
  elseif gKind == 2 then
    -- Every precipitation card uses RainTint now, so shader fallbacks stay format-compatible.
    gSh = getSandShader() or getCardFallbackShader() or getRainShader()
  elseif gKind == 3 then
    -- Leaf shader can fail on a host/GLES reset; a compatible shape shader is
    -- better than no leaves at all. invalidate() clears leafShader so it retries.
    gSh = getLeafShader() or getSandShader() or getCardFallbackShader() or getRainShader()
  elseif gKind == 4 then
    gSh = getAshShader() or getSandShader() or getCardFallbackShader() or getRainShader()
  end
  if not gSh then return 0, false end
  beginPass(Voxel3D, gSh)
  -- Sand always keeps the normal lequal depth mode installed by beginPass().
  -- A former steep-look override used depth="always", which made downward
  -- camera pitch reveal grit through ground/props and turned a subtle storm
  -- into a dense screen layer.
  -- Colour for the whole family pass. UV/falloff data occupies the available
  -- vertex channels, so each grain family is submitted separately with a stable
  -- tint. Multiple families may coexist in the same frame.
  local tintKind=(gKind==1 and "hail") or (gKind==2 and "sand") or (gKind==3 and "debris") or "ash"
  local tr,tg,tb=celestialTint(tintKind,grainR,grainG,grainB)
  V.safeCall(love.graphics.setColor,tr,tg,tb,1)
  local okDraw = V.safeCall(love.graphics.draw, grainMesh)
  V.safeCall(love.graphics.setColor, 1, 1, 1, 1)
  endPass(Voxel3D)
  if okDraw and gKind then
    drawnGrainVerts[gKind] = (drawnGrainVerts[gKind] or 0) + buf.n
    return buf.n, true
  end
  return 0, false
end

function WP._drawProceduralGrain(Voxel3D,kind,ex,ey,ez)
  local count=(grain.gpuTarget and grain.gpuTarget[kind]) or 0
  if count<=0 then return true,0 end
  local PP=WP._proceduralPrecipModule();if not(PP and PP.draw)then return false,0 end
  local focus=lastStreamFocus or WP._procScratch.zero3;local name=(kind==1 and "hail")or(kind==2 and "sand")or"ash"
  local r,g,b=(kind==1 and .90 or kind==2 and .85 or .62),(kind==1 and .95 or kind==2 and .72 or .62),(kind==1 and 1.0 or kind==2 and .48 or .60)
  r,g,b=celestialTint(name,r,g,b)
  local top=precipDeckY or ((focus[2] or 0)+((kind==1)and 24 or SNOW_CEIL)*WP._cloudHeightScale())
  local span=precipDeckSpan or ((kind==1)and 110 or SNOW_CEIL_SPAN)
  -- Legacy source gate / semantic marker: PP.draw uses wind={grain.lastWindX or 0,grain.lastWindZ or 0}
  local o=WP._procVectors(WP._procScratch.grainDraw,ex,ey,ez,grain.lastWindX,grain.lastWindZ,r,g,b)
  o.kind=name;o.count=count;o.focus=focus;o.nearRadius=(grain.gpuFullVisual and grain.gpuFullVisual[kind]) and 4 or (grain.simRadius[kind] or 96)
  o.farRadius=(grain.visualRadius[kind] or grain.simRadius[kind] or STREAM_RADIUS);o.topY=top;o.bottomY=(focus[2] or 0)-GROUND_DROP;o.span=span;o.time=simTime;o.intensity=grain.intensity[kind] or 0
  o.uniformField=WP._uniformPrecipField==true;o.worldGrid=(WP._uniformPrecipField==true and kind~=3)
  local ok,healthy,n=V.safeCall(PP.draw,Voxel3D,o)
  return ok and healthy==true and (tonumber(n)or 0)==count,tonumber(n)or 0
end

local function drawGrains(Voxel3D)
  for k = 1, 4 do
    drawnGrainVerts[k] = 0
    drawnGrainHealthy[k] = false
  end
  local target = grain.target
  local simTarget=grain.simTarget
  local eye = Voxel3D.eye
  local ex, ey, ez = eye and (eye[1] or 0) or 0, eye and (eye[2] or 0) or 0, eye and (eye[3] or 0) or 0
  -- Prove the shared hail/sand/ash procedural renderer with one invisible
  -- instance before any family is allowed to drop its CPU visual population.
  local PP=WP._proceduralPrecipModule();local pst=(PP and PP.stats and PP.stats()) or nil
  if PP and PP.probe and (not pst or (not pst.proven and not pst.failed)) and (((target[1] or 0)>1200) or ((target[2] or 0)>1200) or ((target[4] or 0)>1200)) then
    local focus=lastStreamFocus or WP._procScratch.zero3
    local o=WP._procVectors(WP._procScratch.grainProbe,ex,ey,ez,grain.lastWindX,grain.lastWindZ,1,1,1)
    o.kind="hail";o.focus=focus;o.nearRadius=4;o.farRadius=(grain.simRadius[1] or STREAM_RADIUS)
    o.topY=precipDeckY or ((focus[2] or 0)+24*WP._cloudHeightScale());o.bottomY=(focus[2] or 0)-GROUND_DROP
    o.span=precipDeckSpan or 110;o.time=simTime;o.intensity=1;o.uniformField=WP._uniformPrecipField==true
    V.safeCall(PP.probe,Voxel3D,o)
  end
  if (target[1] or 0) > 0 then
    local a, b = grain.start[1] or 1, (grain.start[1] or 1) + (simTarget[1] or 0) - 1
    local ok=true
    if (simTarget[1] or 0)>0 then local _,v=drawGrainPass(Voxel3D,1,nil,a,b,ex,ey,ez);ok=v end
    local farOK,farN=WP._drawProceduralGrain(Voxel3D,1,ex,ey,ez)
    drawnGrainVerts[1]=(drawnGrainVerts[1] or 0)+farN*6
    drawnGrainHealthy[1] = (ok and farOK) and true or false
  end
  if (target[2] or 0) > 0 then
    local a, b = grain.start[2] or 1, (grain.start[2] or 1) + (simTarget[2] or 0) - 1
    local ok=true
    if (simTarget[2] or 0)>0 then local _,v=drawGrainPass(Voxel3D,2,nil,a,b,ex,ey,ez);ok=v end
    local farOK,farN=WP._drawProceduralGrain(Voxel3D,2,ex,ey,ez)
    drawnGrainVerts[2]=(drawnGrainVerts[2] or 0)+farN*6
    drawnGrainHealthy[2] = (ok and farOK) and true or false
  end
  if (target[3] or 0) > 0 then
    local a, b = grain.start[3] or 1, (grain.start[3] or 1) + (simTarget[3] or 0) - 1
    local _, ok = drawGrainPass(Voxel3D, 3, nil, a,b,ex,ey,ez)
    drawnGrainHealthy[3] = ok and true or false
  end
  if (target[4] or 0) > 0 then
    local a, b = grain.start[4] or 1, (grain.start[4] or 1) + (simTarget[4] or 0) - 1
    local okLight,okDark=true,true
    if (simTarget[4] or 0)>0 then
      local _,v1=drawGrainPass(Voxel3D,4,"light",a,b,ex,ey,ez);okLight=v1
      local _,v2=drawGrainPass(Voxel3D,4,"dark",a,b,ex,ey,ez);okDark=v2
    end
    local farOK,farN=WP._drawProceduralGrain(Voxel3D,4,ex,ey,ez)
    drawnGrainVerts[4]=(drawnGrainVerts[4] or 0)+farN*6
    drawnGrainHealthy[4] = (okLight and okDark and farOK) and true or false
  end
end

-- ---------------------------------------------------------------------------
-- PUBLIC DRAW
-- ---------------------------------------------------------------------------
function WP.draw(Voxel3D, frame)
  if not Voxel3D then return end
  -- The update path already freezes the world field during battle. Keep draw
  -- fail-closed too so a host that calls the world atmosphere during its battle
  -- transition cannot paint one stale overworld snow frame over the battle.
  if battleActive() then
    drawnRainVerts,drawnSnowVerts=0,0
    drawnRainHealthy,drawnSnowHealthy=false,false
    for k=1,4 do drawnGrainVerts[k]=0;drawnGrainHealthy[k]=false end
    return
  end
  wpDrawSerial = wpDrawSerial + 1
  -- Record the eye for the next update's face-contact test. Draw is the only
  -- place the eye is available, and it is used purely as a *reader* — placement
  -- and orientation of the simulation still never consult it.
  if Voxel3D.eye then lastEye = Voxel3D.eye end
  do
    local e, f = Voxel3D.eye, Voxel3D.focus
    if e and f then
      local dx = (tonumber(f[1]) or 0) - (tonumber(e[1]) or 0)
      local dy = (tonumber(f[2]) or 0) - (tonumber(e[2]) or 0)
      local dz = (tonumber(f[3]) or 0) - (tonumber(e[3]) or 0)
      local l = sqrt(dx * dx + dy * dy + dz * dz)
      if l > 1e-6 then lastLookY = dy / l end
    end
  end
  -- Track how far the host is actually rendering, so the snow volume can match
  -- it. Same source NightSky and CelestialBodies read for the sky radius.
  local f = Voxel3D.far or (Voxel3D.camera and Voxel3D.camera.far)
  if type(f) == "number" and f > 80 then lastFar = f end

  local weather = (frame and frame.weather) or {}
  local wxId = authoritativeWeatherId(weather)
  local rainI, snowI, hailI, sandI, ashI, debrisI
  rainI, snowI, hailI, sandI, ashI, debrisI, wxId = resolveFamilyIntensities(weather, wxId)
  if isRainOnlyWx(wxId) or wxId == "HAIL" then
    snowI = 0
  elseif isSnowyWx(wxId) then
    if snowI <= 0.02 and weather._wxChannelsResolved ~= true and weather._snowExplicitOff ~= true then snowI = snowyTarget(wxId) end
  elseif snowI <= 0.02 then
    snowI = 0
  end

  drawWetMarks(Voxel3D)
  do local PI=WP._interactionPrecip();if PI and PI.draw then PI.draw(Voxel3D) end end
  drawGroundSnow(Voxel3D)
  drawFootprints(Voxel3D)
  -- 8.1.76: update() is the precipitation ownership authority. Do not gate the
  -- draw pass a second time from the frame-local weather bag: that bag can be
  -- transiently zero/clear for one pose or ledge-hop frame even though update()
  -- correctly kept the rain stream alive. If update allocated rain this frame,
  -- draw it. Explicit OFF / real transitions already drive rain.active to zero.
  if (rain.active or 0) > 0 and (tonumber(rain.lastIntensity) or 0) > 0.02 then
    drawRainStreaks(Voxel3D)
    -- Lens droplets are drawn for rain too, not just snow.
    drawFaceSpecks(Voxel3D)
  else
    drawnRainVerts = 0
    drawnRainHealthy = false
  end
  if snowI > 0.02 then
    drawSnowFlakes(Voxel3D)
    drawFaceSpecks(Voxel3D)
  else
    -- Belt and braces. `snow.active` drops to 0 in update() when the weather
    -- stops being snowy, and drawingSnow() checks that too, so this is not the
    -- only thing standing between clear weather and a suppressed 2D layer --
    -- but a stale vertex count is a trap for the next reader either way.
    drawnSnowVerts = 0
    drawnSnowHealthy = false
  end
  if hailI > 0.02 or sandI > 0.02 or ashI > 0.02 or debrisI > 0.02 then
    drawGrains(Voxel3D)
  else
    for k = 1, 4 do
      drawnGrainVerts[k] = 0
      drawnGrainHealthy[k] = false
    end
  end
end

function WP.markDrawFailed()
  -- Draw ownership is a safety signal, not simulation state. If a host/shader
  -- call fails, immediately revoke 3D ownership without throwing away particle
  -- positions; the next healthy frame can resume seamlessly while Draw keeps
  -- the 2D fallback visible in the meantime.
  drawnRainVerts = 0
  drawnSnowVerts = 0
  drawnRainHealthy = false
  drawnSnowHealthy = false
  for k = 1, 4 do
    drawnGrainVerts[k] = 0
    drawnGrainHealthy[k] = false
  end
  lastEye = nil
end

-- Release 3D falling-weather working sets when no enabled feature consumes them.
-- Persistent SnowPack/world accumulation is deliberately NOT cleared: toggling
-- presentation must not melt/reset authored world state. Only transient falling
-- particles, GPU resources and interaction marks are retired.
function WP.suspend()
  rain.active,rain.simActive,rain.gpuActive,rain.gpuFullVisual=0,0,0,false
  snow.active,snow.simActive,snow.gpuActive,snow.gpuFullVisual=0,0,0,false
  grain.active=0
  for k=1,4 do grain.target[k],grain.simTarget[k],grain.gpuTarget[k],grain.gpuFullVisual[k]=0,0,0,false end
  wet.active,face.active=0,0
  drawnRainVerts,drawnSnowVerts=0,0
  drawnRainHealthy,drawnSnowHealthy=false,false
  for k=1,4 do
    drawnGrainVerts[k]=0
    drawnGrainHealthy[k]=false
  end
  WP._trimPool(rain,0,"rain")
  WP._trimPool(snow,0,"snow")
  WP._trimPool(grain,0,"grain")
  WP.invalidate()
  return true
end

function WP.invalidate()
  -- GPU resources only. Particle positions, velocities, and active counts
  -- stay alive so weather continues seamlessly across map loads / GL resets.
  -- Wiping the pools here is what made precipitation "restart" on every
  -- route change.
  rainMesh, snowMesh, wetMesh, grainMesh, gsnowMesh, footMesh, faceMesh = nil, nil, nil, nil, nil, nil, nil
  WP._gsnowMeshRevision=nil
  rainShader, cardFallbackShader, snowShader, snowShaderBall, grainShader = nil, nil, nil, nil, nil
  snowInstance.base,snowInstance.instances,snowInstance.shader,snowInstance.shaderBall=nil,nil,nil,nil
  snowInstance.cap=0; snowInstance.failed=false
  local PS=WP._proceduralSnowModule(); if PS and PS.invalidate then V.safeCall(PS.invalidate) end
  local PP=WP._proceduralPrecipModule(); if PP and PP.invalidate then V.safeCall(PP.invalidate) end
  do local PI=WP._interactionPrecip();if PI and PI.invalidate then V.safeCall(PI.invalidate) end end
  hailShader = nil
  ashShader = nil
  sandShader = nil
  leafShader = nil
  meshCap = {}
  prefixUpload = nil
  vpSentSerial = setmetatable({}, { __mode = "k" })
  vpSendMode = setmetatable({}, { __mode = "k" })
  lastEye = nil
  -- do NOT zero rain.active / snow.active / grain.active / wet / gsnow / face
  -- do NOT clear groundSnowTarget — packs persist across adjacent maps
end


function WP.describe()
  local fate = snowLanded + snowExpiredAir
  return string.format("wp rain=%d snow=%d(sim=%d gpu=%d full=%s v%d) grain=%d gsnow=%d foot=%d face=%d/%d land=%d/%d fpv=%s q=%.2f",
    rain.active or 0, snow.active or 0, snow.simActive or snow.active or 0, snow.gpuActive or 0, tostring(snow.gpuFullVisual==true), drawnSnowVerts,
    grain.active or 0, gsnow.active or 0, foot.active or 0,
    face.active or 0, faceHitTotal,
    snowLanded, fate,
    tostring(fpv), tonumber(qBudget.worldPrecip) or 1.0)
end

--- True only when flake geometry was actually emitted on the last drawn frame.
--- DramalessAtmos.handlesSnow() uses this to decide whether the 2D snow sheet
--- is redundant. It deliberately reports what happened, not what was intended:
--- "snow intensity is nonzero" was the assumption that let the 2D layer get
--- switched off while the 3D layer was silently failing to load.
--- Share (0..1) of currently live flakes within `radius` of a world XZ point,
--- measured across the WHOLE active pool.
---
--- This exists because the obvious way to check near-field density -- read
--- WP.sample() every frame and count -- is a peephole: sample() returns at most
--- 12 entries and always the same low pool indices, so it is a small correlated
--- sample whose answer swung between 36% and 68% run to run. The near field is
--- the whole point of the FPV rework, so it gets a real statistic rather than
--- one that has to be eyeballed for flakiness.
function WP.snowNearShare(px, pz, radius)
  local active = snow.active or 0
  local simActive=snow.simActive or active
  if active <= 0 then return 0, 0 end
  local r2 = (radius or 25) * (radius or 25)
  local sxa, sza = snow.x, snow.z
  local hits = 0
  for i = 1, simActive do
    local dx, dz = sxa[i] - px, sza[i] - pz
    if (dx * dx + dz * dz) < r2 then hits = hits + 1 end
  end
  return hits / active, active
end

--- Flakes per 1000 square world units inside the annulus [r0, r1).
--- The statistic that says whether it is snowing over the world or only on the
--- player: for a correct field this is the same number in every annulus.
function WP.snowAreaDensity(px, pz, r0, r1)
  local active = snow.active or 0
  if active <= 0 or r1 <= r0 then return 0 end
  -- Procedural far snow is analytically uniform by area. Reporting its designed
  -- density avoids pretending that a CPU-only sample can inspect GPU instances.
  if (snow.gpuActive or 0)>0 then
    local fullArea=math.pi*max(1,SNOW_STREAM_RADIUS*SNOW_STREAM_RADIUS-SNOW_MIN_R*SNOW_MIN_R)
    return active*1000.0/fullArea
  end
  local a2, b2 = r0 * r0, r1 * r1
  local sxa, sza = snow.x, snow.z
  local hits = 0
  local simActive=snow.simActive or active
  for i = 1, simActive do
    local dx, dz = sxa[i] - px, sza[i] - pz
    local d2 = dx * dx + dz * dz
    if d2 >= a2 and d2 < b2 then hits = hits + 1 end
  end
  local area = math.pi * (b2 - a2)
  return hits * 1000.0 / area
end

--- How many ground splashes are currently alive. Nonzero means drops are
--- actually reaching the ground plane rather than expiring above it.
function WP.wetActive()
  return wet.active or 0
end

--- Drops that have reached the ground plane and splashed. Unlike wetActive()
--- this counts impacts only, not ambient scatter.
function WP.rainLanded()
  return rainLanded
end

--- Grains per 1000 square world units inside the annulus [r0, r1). Whole-pool,
--- not WP.sample() -- that returns twelve entries from the same low indices and
--- is far too small a sample to measure a radial distribution with.
function WP.grainAreaDensity(px, pz, r0, r1)
  local active = grain.active or 0
  if active <= 0 or r1 <= r0 then return 0 end
  local a2, b2 = r0 * r0, r1 * r1
  local gxa, gza = grain.x, grain.z
  local hits = 0
  for i = 1, active do
    local dx, dz = gxa[i] - px, gza[i] - pz
    local d2 = dx * dx + dz * dz
    if d2 >= a2 and d2 < b2 then hits = hits + 1 end
  end
  return hits * 1000.0 / (math.pi * (b2 - a2))
end

--- Drops per 1000 square world units inside the annulus [r0, r1).
---
--- The rain twin of snowAreaDensity, and it exists for a specific reason: the
--- obvious way to measure rain's radial spread is to poll WP.sample() each
--- frame, but sample() returns 12 entries from the same low pool indices. That
--- is a peephole, not a sample. Measured that way rain's spread bounced between
--- 1.24x and 1.98x across warm-up lengths with no trend -- pure noise that was
--- briefly mistaken for a real distribution problem. Walk the whole pool.
function WP.rainAreaDensity(px, pz, r0, r1)
  local active = rain.active or 0
  if active <= 0 or r1 <= r0 then return 0 end
  if (rain.gpuActive or 0)>0 then return active*1000.0/(math.pi*max(1,STREAM_RADIUS*STREAM_RADIUS-.36)) end
  local a2, b2 = r0 * r0, r1 * r1
  local rxa, rza = rain.x, rain.z
  local hits = 0
  for i = 1, (rain.simActive or active) do
    local dx, dz = rxa[i] - px, rza[i] - pz
    local d2 = dx * dx + dz * dz
    if d2 >= a2 and d2 < b2 then hits = hits + 1 end
  end
  return hits * 1000.0 / (math.pi * (b2 - a2))
end

--- The rain stream radius and the drops-per-tile actually being achieved.
function WP.rainCoverage()
  local r = STREAM_RADIUS
  local tiles = (math.pi * r * r) / (TILE * TILE)
  return r, (rain.active or 0) / max(1, tiles), TILE
end

--- The radius the sim is currently covering, and the flakes-per-tile it is
--- achieving there. Both are derived at runtime from the host's far plane, so
--- this is the only honest way to report them.
function WP.snowCoverage()
  local r = SNOW_STREAM_RADIUS
  local tiles = (math.pi * r * r) / (TILE * TILE)
  return r, (snow.active or 0) / max(1, tiles)
end

--- How many flakes finished their life on the ground versus in mid air.
--- Used by the test suite; also the fastest way to tell from the debug HUD
--- whether snow is actually reaching the world or just decorating the air.
--- Deepest a flake has descended below the focus (world units), and the ground
--- plane it is aiming for. Behavioural, not declarative: this reports where
--- flakes got to, so a change to GROUND_DROP that the sim does not actually
--- honour shows up as a discrepancy rather than passing silently.
function WP.snowDepth()
  return snowDeepest, GROUND_DROP, TILE
end

function WP.snowFate()
  return snowLanded, snowExpiredAir
end

--- True only when rain geometry was actually emitted on the last drawn frame.
--- The twin of drawingSnow(), and it exists for the same reason: the 2D rain
--- gate in Draw used to test `VoxelAtmos.active or VoxelAtmos.handlesPrecipitation`
--- -- FUNCTION REFERENCES, never called, so always truthy. That gate could not
--- fail, which meant it never actually checked anything.
function WP.drawingRain()
  -- Health, not visible-vertex count, owns the 2D fallback. A healthy family
  -- may submit zero vertices when every particle is conservatively culled behind
  -- the camera; drawing 2D in that case would create a screen-space overlay.
  return (rain.active or 0) > 0 and drawnRainHealthy == true
end

--- True only when the requested grain family submitted geometry on the most
--- recent 3D draw. This is deliberately behavioural: a nonzero intensity is
--- not proof that a shader/mesh/host draw actually happened.
function WP.drawingGrain(kind)
  kind = tonumber(kind)
  if not kind or kind < 1 or kind > 4 then return false end
  local target = grain.target and (grain.target[kind] or 0) or 0
  return target > 0 and drawnGrainHealthy[kind] == true
end

function WP.drawingLeaves()
  return WP.drawingGrain(3)
end

--- True only when EVERY active precipitation family requested by the current
--- 3D simulation actually submitted geometry. DramalessAtmos uses this as the
--- authority for suppressing the 2D safety layer. Any missing pass returns
--- false so the player gets visible 2D weather instead of an invisible effect.
function WP.drawingAllRequested()
  if lastEye == nil then return false end
  local any = false
  if (rain.active or 0) > 0 then
    any = true
    if not WP.drawingRain() then return false end
  end
  if (snow.active or 0) > 0 then
    any = true
    if not WP.drawingSnow() then return false end
  end
  local target = grain.target or {}
  for kind = 1, 4 do
    if (target[kind] or 0) > 0 then
      any = true
      if not WP.drawingGrain(kind) then return false end
    end
  end
  return any
end

--- Debug/test surface: requested and successfully submitted counts per family.
function WP.grainStatus()
  local target = grain.target or {}
  return {
    hail={target=target[1] or 0,simulated=grain.simTarget[1] or 0,procedural=grain.gpuTarget[1] or 0,verts=drawnGrainVerts[1] or 0},
    sand={target=target[2] or 0,simulated=grain.simTarget[2] or 0,procedural=grain.gpuTarget[2] or 0,verts=drawnGrainVerts[2] or 0},
    debris={target=target[3] or 0,simulated=grain.simTarget[3] or 0,procedural=grain.gpuTarget[3] or 0,verts=drawnGrainVerts[3] or 0},
    ash={target=target[4] or 0,simulated=grain.simTarget[4] or 0,procedural=grain.gpuTarget[4] or 0,verts=drawnGrainVerts[4] or 0},
  }
end

--- True at voxel tilt 75, third person and first person; false at 15/35/50.
--- Defaults to TRUE when the look direction is unknown, because the immersive
--- path is what every other camera-aware behaviour here already assumes.
function WP.immersiveCamera()
  if lastLookY == nil then return true end
  return lastLookY > IMMERSIVE_SIN
end

function WP.liveCounts(out)
  out=out or {}
  local target=grain.target or {}
  out.rain=rain.active or 0
  out.snow=snow.active or 0
  out.hail=target[1] or 0
  out.sand=target[2] or 0
  out.debris=target[3] or 0
  out.ash=target[4] or 0
  out.groundSnow=gsnow.active or 0
  out.footprints=foot.active or 0
  out.wet=wet.active or 0
  return out
end

-- 8.2.10 on-demand leaf-size diagnostic. This performs no work in the normal
-- update/draw path. It reports each sampled leaf's intrinsic base size and the
-- presentation size derived from its CURRENT eye distance, which lets live QA
-- prove that a far-born leaf grows correctly as it approaches the player.
function WP.leafSizeSamples(limit)
  limit=min(max(1,floor(tonumber(limit) or 8)),512)
  local out={}
  local eye=lastEye or {0,0,0}
  local ex,ey,ez=eye[1] or 0,eye[2] or 0,eye[3] or 0
  local DEPTH=STREAM_RADIUS*1.15
  local n=0
  for i=1,(grain.active or 0) do
    if grain.kind[i]==3 then
      local dx,dy,dz=ex-(grain.x[i] or 0),ey-(grain.y[i] or 0),ez-(grain.z[i] or 0)
      local dist=sqrt(dx*dx+dy*dy+dz*dz)
      local near=1.0-min(1.0,dist/DEPTH)
      local distanceScale=0.40+near*1.35
      local seed=grain.seed[i] or 0.5
      local cardScale=1.15+seed*0.25
      local base=grain.size[i] or 0
      n=n+1
      out[n]={
        index=i,id=grain.id[i] or i,
        x=grain.x[i],y=grain.y[i],z=grain.z[i],seed=seed,
        distance=dist,baseSize=base,distanceScale=distanceScale,
        displayLength=base*distanceScale*cardScale,
        alpha=grain.a[i] or 0,settled=grain.leafSettled[i]==true,
      }
      if n>=limit then break end
    end
  end
  return out
end

-- On-demand diagnostic for tests/DEBUG. This deliberately performs no work in
-- the normal frame path; callers can verify that live physical rain spans the
-- expected vertical column without confusing mesh submission with visibility.
function WP.rainColumnRange()
  local n = rain.simActive or rain.active or 0
  if n <= 0 then return nil, nil, 0, precipDeckY, precipDeckSpan end
  local lo, hi = 1e30, -1e30
  for i = 1, n do
    local y = rain.y[i]
    if y and y < lo then lo = y end
    if y and y > hi then hi = y end
  end
  if lo == 1e30 then return nil, nil, 0, precipDeckY, precipDeckSpan end
  return lo, hi, n, precipDeckY, precipDeckSpan
end

function WP.spawnStatus()
  local target = grain.target or {}
  return {
    wxId = tostring((V and V.weatherFxId) or ""),
    rain = rain.active or 0,
    snow = snow.active or 0,
    hail = target[1] or 0,
    sand = target[2] or 0,
    debris = target[3] or 0,
    ash = target[4] or 0,
  }
end

-- Runtime submission proof. Counts here are written only by the actual draw
-- functions after mesh upload + love.graphics.draw succeeds. This lets the
-- debug/audit path distinguish "weather requested" from "particles allocated"
-- and from "geometry really submitted".
function WP.drawStatus()
  local target = grain.target or {}
  return {
    rain = { active=rain.active or 0, simulated=rain.simActive or rain.active or 0, procedural=rain.gpuActive or 0, verts=drawnRainVerts or 0, healthy=drawnRainHealthy == true, fieldBottomY=rain.fieldBottomY, coverageMode=(WP._uniformPrecipField==true and 'render-grid' or 'regional'), renderRadius=STREAM_RADIUS },
    snow = { active=snow.active or 0, simulated=snow.simActive or snow.active or 0, procedural=snow.gpuActive or 0, verts=drawnSnowVerts or 0, healthy=drawnSnowHealthy == true, fullVisual=snow.gpuFullVisual==true, cpuFallback=(snow.active or 0)>0 and snow.gpuFullVisual~=true },
    hail = { active=target[1] or 0, simulated=grain.simTarget[1] or 0, procedural=grain.gpuTarget[1] or 0, verts=drawnGrainVerts[1] or 0, healthy=drawnGrainHealthy[1] == true },
    sand = { active=target[2] or 0, simulated=grain.simTarget[2] or 0, procedural=grain.gpuTarget[2] or 0, verts=drawnGrainVerts[2] or 0, healthy=drawnGrainHealthy[2] == true },
    debris = { active=target[3] or 0, simulated=grain.simTarget[3] or 0, procedural=grain.gpuTarget[3] or 0, verts=drawnGrainVerts[3] or 0, healthy=drawnGrainHealthy[3] == true },
    ash = { active=target[4] or 0, simulated=grain.simTarget[4] or 0, procedural=grain.gpuTarget[4] or 0, verts=drawnGrainVerts[4] or 0, healthy=drawnGrainHealthy[4] == true },
  }
end

function WP.drawingSnow()
  -- Successful 3D path owns snow even when the camera culls every flake. Actual
  -- upload/draw failures still leave this false and restore the 2D safety layer.
  return (snow.active or 0) > 0 and drawnSnowHealthy == true
end

--- Sample independent particle identities (debug HUD / tests).
function WP.sample(limit)
  limit = min(limit or 6, 12)
  local out = {}
  local n = 0
  for i = 1, (rain.simActive or rain.active or 0) do
    if n >= limit then break end
    n = n + 1
    out[n] = string.format(
      "Rain#%d pos=(%.1f,%.1f,%.1f) vel=(%.1f,%.1f,%.1f) life=%.2f/%.2f",
      rain.id[i] or i, rain.x[i], rain.y[i], rain.z[i],
      rain.vx[i], rain.vy[i], rain.vz[i],
      rain.life[i] or 0, rain.maxLife[i] or 0)
  end
  for i = 1, (snow.simActive or snow.active or 0) do
    if n >= limit then break end
    n = n + 1
    out[n] = string.format(
      "Snow#%d pos=(%.1f,%.1f,%.1f) vel=(%.1f,%.1f,%.1f) life=%.2f/%.2f",
      snow.id[i] or i, snow.x[i], snow.y[i], snow.z[i],
      snow.vx[i], snow.vy[i], snow.vz[i],
      snow.life[i] or 0, snow.maxLife[i] or 0)
  end
  for i = 1, (grain.active or 0) do
    if n >= limit then break end
    n = n + 1
    local kn = ({[1]="Hail",[2]="Sand",[3]="Leaf",[4]="Ash",[5]="BlkAsh"})[grain.kind[i] or 2] or "Grain"
    out[n] = string.format(
      "%s#%d pos=(%.1f,%.1f,%.1f) vel=(%.1f,%.1f,%.1f) life=%.2f/%.2f",
      kn, grain.id[i] or i, grain.x[i], grain.y[i], grain.z[i],
      grain.vx[i], grain.vy[i], grain.vz[i],
      grain.life[i] or 0, grain.maxLife[i] or 0)
  end
  return out
end

--- Live tuning hook. The snow numbers live here rather than baked in because
--- none of them can be validated without a human looking at the screen.
function WP.tune(t)
  if type(t) ~= "table" then return false end
  if tonumber(t.radius) then
    -- An explicit radius pins the volume: clear the tracked far plane, or the
    -- next update would immediately recompute over the top of it.
    SNOW_STREAM_RADIUS = max(40, tonumber(t.radius))
    SNOW_DRAW_RADIUS = SNOW_STREAM_RADIUS
    lastFar = nil
  end
  if tonumber(t.drawRadius) then SNOW_DRAW_RADIUS = max(20, tonumber(t.drawRadius)) end
  if tonumber(t.bias) then SNOW_RADIAL_BIAS = max(0.3, tonumber(t.bias)) end
  if tonumber(t.max) then SNOW_MAX = max(64, floor(tonumber(t.max))) end
  if tonumber(t.ceil) then SNOW_CEIL = tonumber(t.ceil) end
  if tonumber(t.ceilSpan) then SNOW_CEIL_SPAN = tonumber(t.ceilSpan) end
  if tonumber(t.perTile) then SNOW_PER_TILE = max(0.05, tonumber(t.perTile)) end
  if tonumber(t.groundTiles) then
    GROUND_EXTRA_TILES = tonumber(t.groundTiles)
    GROUND_DROP = 1.5 + GROUND_EXTRA_TILES * TILE
  end
  if tonumber(t.faceRadius) then
    FACE_R = max(0, tonumber(t.faceRadius))
    FACE_R2 = FACE_R * FACE_R
  end
  return true
end

--- Exposed for the test suite: what the module thinks a WX id means, and the
--- current snow tunables. `fhash` is exported so it has a caller and cannot be
--- mistaken for the dead helper it replaced.
WP.snowyTarget = snowyTarget
WP.hash = fhash
function WP.precipVirtualization()
  local PP=WP._proceduralPrecipModule();local ps=(PP and PP.stats and PP.stats()) or {}
  return {rain={logical=rain.active or 0,simulated=rain.simActive or rain.active or 0,procedural=rain.gpuActive or 0,radius=rain.simRadius or STREAM_RADIUS,fullVisual=rain.gpuFullVisual==true,pool=rain.n or 0,fieldBottomY=rain.fieldBottomY,cpuAnchorX=rain.cpuAnchorX,cpuAnchorZ=rain.cpuAnchorZ,cpuAnchorCell=rain.cpuAnchorCell},grain={logical=grain.target,simulated=grain.simTarget,procedural=grain.gpuTarget,fullVisual=grain.gpuFullVisual,radius=grain.simRadius,visualRadius=grain.visualRadius,pool=grain.n or 0},backend=ps}
end

function WP.snowVirtualization()
  local PS=WP._proceduralSnowModule()
  local ps=(PS and PS.stats and PS.stats()) or {}
  return {logical=snow.active or 0,simulated=snow.simActive or snow.active or 0,procedural=snow.gpuActive or 0,simRadius=snow.simRadius or SNOW_STREAM_RADIUS,fieldRadius=SNOW_STREAM_RADIUS,fullVisual=snow.gpuFullVisual==true,pool=snow.n or 0,groundCollision=snow.gpuFullVisual~=true,cpuFallback=(snow.active or 0)>0 and snow.gpuFullVisual~=true,backend=ps}
end

function WP.snowGroundCollisionEnabled() return true end

function WP.snowTunables()
  return {
    radius = SNOW_STREAM_RADIUS, drawRadius = SNOW_DRAW_RADIUS,
    bias = SNOW_RADIAL_BIAS, max = SNOW_MAX,
    ceil = SNOW_CEIL * WP._cloudHeightScale(), ceilBase = SNOW_CEIL, ceilSpan = SNOW_CEIL_SPAN,
    perTile = SNOW_PER_TILE, groundTiles = GROUND_EXTRA_TILES,
    groundDrop = GROUND_DROP,
    faceRadius = FACE_R,
  }
end

return WP
