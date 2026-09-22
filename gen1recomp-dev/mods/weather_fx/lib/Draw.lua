-- THE PASS: everything that happens to a frame, in the order it happens.
--
-- Both whole-frame stages -- `worldPresent` over a world pipeline's canvas
-- and `present` over the flat composite -- call exactly this one function
-- with a different rectangle, so there is ONE description of what weather
-- looks like and no chance of the renderers drifting apart.  The battle
-- screen has its own small compositor (lib/BattleDraw.lua) because it
-- draws in a different coordinate space.
--
-- THE ORDER IS THE POINT:
--
--   1. TIME-OF-DAY GRADE, multiplied.  Under everything, because the
--      time of day is a property of the light in the world, not of the
--      water in front of it: rain lit by a sun that set an hour ago
--      should be dark, and a grade over the top would dim the drops too.
--   2. WEATHER GRADE, also multiplied.  The gloom of the storm, on top of
--      the hour.  Two multiplies rather than one combined colour because
--      they have different lifetimes -- the hour eases over minutes, the
--      storm over seconds -- and combining them would mean recomputing
--      both whenever either moved.
--   3. FOG banks, between the world and the falling water.
--   4. VEIL, the flat achromatic haze a whiteout or a real murk has, over
--      the banks so it flattens them too.
--   5. PRECIPITATION, in front of all of it.
--   6. GLARE, an additive bloom, over the water: sunlight is on the lens,
--      not in the scene.
--   7. LIGHTNING, over everything including the rain, because a strike
--      lights the drops as well as the ground.
--
-- STATE IS FENCED AT BOTH ENDS.  The engine already wraps a pipeline
-- callback in love.graphics.push("all")/pop() so a mod cannot leak a bound
-- shader into the composite, but this restores blend mode, colour and
-- scissor itself anyway: worldPresent hands its canvas onward to the UI
-- composite within the same frame, and a mod that relies on somebody
-- else's cleanup is a mod that breaks when the cleanup moves.

local V = ...
local Harden = nil
pcall(function() Harden = V.require("Harden") end)
local Scene = V.require("Scene")
local State = V.require("WeatherState")
local Types = V.require("Types")
local Settings = V.require("Settings")
local Config = V.require("Config")
local Quality = V.require("Quality")
local Particles = V.require("Particles")
local Lightning = V.require("Lightning")
local Fog = V.require("Fog")
local Audio = V.require("Audio")
local Atmos = nil
pcall(function() Atmos = V.require("DramalessAtmos") end)
local TOD = V.require("TimeOfDay")
local BattleDraw = V.require("BattleDraw")
local Legendary = V.require("Legendary")
local Funnel = V.require("Funnel")
local NpcLightning2D = nil
pcall(function() NpcLightning2D = V.require("NpcLightning2D") end)

local MesoscaleCached = false
local function mesoscaleField()
  if MesoscaleCached then return MesoscaleCached end
  local ok,m=pcall(V.require,"MesoscaleField")
  if ok and m then MesoscaleCached=m; return m end
  return nil
end

local WindEngineCached = false
local function windEngine()
  if WindEngineCached then return WindEngineCached end
  local ok, m = pcall(V.require, "WindEngine")
  if ok and m then WindEngineCached = m; return m end
  return nil -- retry later if host/module load order was not ready yet
end

-- Optional 3D atmosphere bridge (Kanto path). Loaded lazily / safely so a
-- missing module never breaks the post-process compositor.
local VoxelAtmos = nil
do
  local ok, mod = pcall(V.require, "VoxelAtmosBridge")
  if ok then VoxelAtmos = mod end
end

local Draw = {}

-- Cosmetic draw isolation. A single optional helper (fog, glare, lightning,
-- funnel, etc.) must never retire the whole weather pipeline for the session.
-- Harden.call logs through the mod logger; the pcall fallback keeps the same
-- fail-soft contract in tests/older hosts where Harden is unavailable.
local function guarded(label, fn, ...)
  if type(fn) ~= "function" then return false end
  if Harden and Harden.call then return Harden.call(label, fn, ...) end
  return pcall(fn, ...)
end

-- True only for the overworld when the 3D bridge is actively drawing the
-- corresponding layer. Battles always keep the 2D overlays.
-- Explicit 3D is an AUTHORITATIVE presentation mode, not a preference.
--
-- AUTO intentionally keeps the per-family 2D fail-safe below: if a shader,
-- mesh, or host pass fails, the affected family can fall back to 2D instead of
-- becoming invisible. But when the player selects WX PRESENT = 3D (or enters
-- first person, which also forces 3D), a healthy voxel bridge owns the entire
-- Weather FX overworld presentation. In that state NO screen-space Weather FX
-- compositor is allowed to stack over the voxel scene.
--
-- Fail open only when there is no active 3D host at all. That preserves useful
-- weather on unsupported hosts instead of turning explicit 3D into a blank sky.
local function worldBackedBattle3d()
  return Scene.now.visible == "battle" and Scene.now.battleOpaque == false
end

local function strict3dPresent()
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  if not (Settings.force3dPresent and Settings.force3dPresent()) then return false end
  return (VoxelAtmos and VoxelAtmos.active and VoxelAtmos.active()) and true or false
end

Draw._strict3dPresent = strict3dPresent

local function use3dPrecip()
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  -- Player chose original 2D Weather FX overlays.
  if Settings.force2dPresent and Settings.force2dPresent() then return false end
  if VoxelAtmos and VoxelAtmos.handlesPrecipitation and VoxelAtmos.handlesPrecipitation() then
    return true
  end
  -- The FPV fallback that used to live here read:
  --     if VoxelAtmos and (VoxelAtmos.active or VoxelAtmos.handlesPrecipitation)
  -- Those are FUNCTION REFERENCES, never called. Both exist whenever the bridge
  -- module is loaded, so the test was always true and this gate could not fail
  -- -- it never checked anything. That cuts both ways: it suppressed the 2D
  -- rain layer in first person even when no 3D rain was drawing at all, which
  -- would leave a rainstorm with no rain in it.
  --
  -- handlesPrecipitation() now reports what WorldPrecip actually emitted, so
  -- the honest answer is simply to trust it and drop the shortcut.
  return false
end

-- Snow has its own gate. use3dPrecip() is rain-family: DramalessAtmos's
-- handlesPrecipitation() only answers true for RAIN/STORM/SLEET/VERDANT_RAIN/
-- PSYSTORM, so routing snow through it meant the 2D snow sheet was never
-- suppressed and drew over the 3D flakes.
--
-- Unlike the rain gate this does NOT have an "FPV + bridge present" fallback.
-- That shortcut assumes 3D is drawing because it could be; for snow we ask the
-- thing that knows -- WorldPrecip reports whether it actually emitted flake
-- geometry last frame. If 3D snow is not on screen the 2D sheet stays, so a
-- failed load or a culled field never leaves the player in a silent blizzard.
local function use3dSnow()
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  if Settings.force2dPresent and Settings.force2dPresent() then return false end
  return (VoxelAtmos and VoxelAtmos.handlesSnow and VoxelAtmos.handlesSnow()) and true or false
end

-- Grain families are independently owned in 3D. A mixed weather can render
-- sand successfully while its leaf pass fails; only the failed family should
-- fall back to 2D. Kind ids: 1 hail, 2 sand, 3 leaves/debris, 4 ash.
local function use3dGrain(kind)
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  if Settings.force2dPresent and Settings.force2dPresent() then return false end
  return (VoxelAtmos and VoxelAtmos.handlesGrains
          and VoxelAtmos.handlesGrains(kind)) and true or false
end

local filteredChannelsScratch = {}
local function copyChannelsScratch(ch)
  local out=filteredChannelsScratch
  for k in pairs(out) do out[k]=nil end
  for k,v in pairs(ch) do out[k]=v end
  return out
end
local function filtered2dPrecipChannels(ch)
  if type(ch) ~= "table" then return ch end
  -- Explicit 3D means exactly that: no 2D precipitation at all while the 3D
  -- bridge is healthy/active. AUTO retains the family-by-family fail-safe.
  if strict3dPresent() then
    local out = copyChannelsScratch(ch)
    out.rain, out.snow, out.hail = 0, 0, 0
    out.sand, out.debris, out.ash = 0, 0, 0
    return out
  end
  local out = ch
  local copied = false
  local function suppress(key, owned)
    if owned and (tonumber(ch[key]) or 0) > 0 then
      if not copied then
        out = copyChannelsScratch(ch)
        copied = true
      end
      out[key] = 0
    end
  end
  suppress("rain", use3dPrecip())
  suppress("snow", use3dSnow())
  suppress("hail", use3dGrain(1))
  suppress("sand", use3dGrain(2))
  suppress("debris", use3dGrain(3))
  suppress("ash", use3dGrain(4))
  return out
end

-- Internal diagnostic surface used by the executable release audit. Keeping
-- the filtering in one function also prevents the normal and diorama passes
-- from drifting apart again.
Draw._filter2dPrecipChannels = filtered2dPrecipChannels

-- 3D world lightning owns the bolt whenever it is running.
--
-- The 2D system builds its bolt in SCREEN space from a 2D point picker
-- (pickFarImpact(viewW, viewH)), so every strike it makes is in front of the
-- player by construction and slides with the camera. That is the overlay this
-- replaces.
--
-- Gated on 3D lightning RUNNING, not on it having drawn this frame: a bolt
-- lasts a fraction of a second, so a per-frame test would let the 2D overlay
-- back in between strikes.
local function use3dLightning()
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  if Settings.force2dPresent and Settings.force2dPresent() then
    -- 8.1.99 mixed presentation: only the bolt may opt into the world-space
    -- renderer while classic 2D precipitation/fog remain authoritative. Fail
    -- open to 2D unless the 3D lightning pass is actually healthy.
    if not (Settings.wants3dLightningWith2dWeather
        and Settings.wants3dLightningWith2dWeather()) then return false end
  end
  return (VoxelAtmos and VoxelAtmos.handlesLightning
          and VoxelAtmos.handlesLightning()) and true or false
end

local function use3dFog()
  if Scene.now.visible == "battle" and not worldBackedBattle3d() then return false end
  if Settings.force2dPresent and Settings.force2dPresent() then return false end
  return VoxelAtmos and VoxelAtmos.handlesFog and VoxelAtmos.handlesFog()
end

-- WHICH WEATHER THIS FRAME IS SHOWING.
--
-- Two authorities, one per context, and never both at once:
--
--   * the overworld's eased channels (WeatherState) for the world;
--   * the BATTLE's eased channels (BattleDraw) whenever a battle is on
--     screen, because a battle's weather comes from
--     `battle.field.weather` and not from the sky outside -- which is
--     what stops a gym battle raining and lets a Rain Dance rain.
--
-- The whole compositor goes through this, so the two can never be mixed
-- inside one frame.
local spatialChannelsScratch={}
function Draw.channels()
  local ch
  local battle=Scene and Scene.now and Scene.now.visible == "battle"
  if battle and BattleDraw and BattleDraw.live then
    local ok, c = pcall(function() return BattleDraw.channels() end)
    if ok then ch = c end
  end
  if type(ch) ~= "table" then ch = (State and State.ch) or {} end
  if type(ch) ~= "table" then ch = {} end
  -- Flat presentation cannot show a rain shaft in the distance, but it can
  -- still represent the weather *where the player is*. Scale only physical
  -- precipitation families by the listener's mesoscale band; battle weather
  -- remains entirely battle-owned.
  if not battle then
    local M=mesoscaleField()
    local ms=M and (not M.ready or M.ready()) and M.peek and M.peek() or nil
    local scale=ms and tonumber(ms.precipScale) or nil
    if scale and math.abs(scale-1)>0.01 then
      local out=spatialChannelsScratch
      for k in pairs(out) do out[k]=nil end
      for k,v in pairs(ch) do out[k]=v end
      out.rain=(tonumber(out.rain) or 0)*scale
      out.snow=(tonumber(out.snow) or 0)*scale
      out.hail=(tonumber(out.hail) or 0)*scale
      return out
    end
  end
  return ch
end

-- The rect the last draw used, so the update tick has somewhere to
-- simulate before the first frame has told it how big the screen is.
local lastRect = { x = 0, y = 0, w = 0, h = 0, scale = 1 }

-- The wind is one slow oscillator shared by rain, snow, grains and
-- (faintly) fog, so everything leans together instead of each system
-- having its own idea of which way the weather is blowing.  Two sines at
-- unrelated periods: enough never to repeat visibly, cheap enough not to
-- care.
local function windAt(t, gust)
  if gust <= 0 then return 0 end
  local slow = math.sin(t * 0.19) * 0.7 + math.sin(t * 0.53 + 1.7) * 0.3
  return slow * 52 * gust        -- GB pixels per second
end

-- THE GLARE GRADIENT.
--
-- This used to be TWO rectangles -- a brighter one over the top 55% of the
-- frame and a dimmer one over the rest -- which put a hard horizontal seam
-- straight across the middle of the screen wherever they met.  Outdoors in
-- rain it was hidden under the precipitation; indoors, where nothing falls
-- but the grade still draws, it was a band across a Poke Mart.
--
-- A four-vertex mesh with per-vertex alpha gives the same "brighter toward
-- the sky" falloff as one continuous ramp, one draw call, and no edge
-- anywhere.  The lesson is small and general: two adjacent fills at
-- different alphas are a seam, not a gradient.
local glare = { mesh = nil, verts={
  {0,0,0,0,1,1,1,1},{0,0,1,0,1,1,1,1},{0,0,1,1,1,1,1,1},{0,0,0,1,1,1,1,1}
} }

local function glareMesh(x, y, w, h, topA, botA)
  if not glare.mesh then
    local ok, made = pcall(function()
      return love.graphics.newMesh({
        { 0, 0, 0, 0, 1, 1, 1, 1 },
        { 1, 0, 1, 0, 1, 1, 1, 1 },
        { 1, 1, 1, 1, 1, 1, 1, 1 },
        { 0, 1, 0, 1, 1, 1, 1, 1 },
      }, "fan", "stream")
    end)
    if not ok then return end
    glare.mesh = made
  end
  local r, g, b = 1.0, 0.94, 0.72
  local v=glare.verts
  v[1][1],v[1][2],v[1][5],v[1][6],v[1][7],v[1][8]=x,y,r,g,b,topA
  v[2][1],v[2][2],v[2][5],v[2][6],v[2][7],v[2][8]=x+w,y,r,g,b,topA
  v[3][1],v[3][2],v[3][5],v[3][6],v[3][7],v[3][8]=x+w,y+h,r,g,b,botA
  v[4][1],v[4][2],v[4][5],v[4][6],v[4][7],v[4][8]=x,y+h,r,g,b,botA
  glare.mesh:setVertices(v)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(glare.mesh)
end

-- WETNESS: the trace rain leaves behind.
--
-- Weather that simply stops does not read as real -- a downpour ends and
-- the world is instantly as dry as if it had never happened.  So the
-- ground REMEMBERS: `wet` rises while rain falls and drains away over a
-- couple of minutes afterwards, and puddles are drawn from it.
--
-- It is not a channel.  Channels belong to a weather and ease toward that
-- weather's value; wetness belongs to the GROUND and outlives the weather
-- entirely -- a channel would be dragged to zero the moment the rain
-- stopped, which is the one thing this must not do.
Draw.wet = 0

-- Puddles only for these overworld weather ids (labels: rain, heavy, primal,
-- storm, psy, sleet, dragon).
local PUDDLE_WEATHER = {
  RAIN_LIGHT = true, RAIN_HEAVY = true, HEAVY_RAIN = true, STORM = true,
  SLEET = true, PSYSTORM = true, DRAGONSTORM = true,
}

function Draw.puddleWeather(id)
  id = tostring(id or ""):upper()
  if PUDDLE_WEATHER[id] then return true end
  -- Soft match on label fragments if a custom id is used
  if id:find("RAIN", 1, true) and not id:find("VERDANT", 1, true) then return true end
  if id == "PSY" or id:find("PSYSTORM", 1, true) then return true end
  if id:find("SLEET", 1, true) then return true end
  if id:find("DRAGON", 1, true) and id:find("STORM", 1, true) then return true end
  return false
end

-- Puddle positions are fixed once and reused, so a puddle stays where it
-- is while the player walks past rather than swimming across the screen.
-- They are anchored to the WORLD by the camera, like the splashes.
local puddles = {}
local PUDDLES = 18
-- Minimum center-to-center distance in screen-space units (1 = full viewport).
local PUDDLE_MIN_DIST = 0.22

local function seedPuddles()
  if #puddles > 0 then return end
  local r = (love and love.math and love.math.random) or math.random
  local tries = 0
  while #puddles < PUDDLES and tries < 800 do
    tries = tries + 1
    local x = r() * 1.6 - 0.3   -- spread across ~1.6 screens
    local y = r() * 1.6 - 0.3
    local ok = true
    for j = 1, #puddles do
      local dx = x - puddles[j].x
      local dy = y - puddles[j].y
      if (dx * dx + dy * dy) < (PUDDLE_MIN_DIST * PUDDLE_MIN_DIST) then
        ok = false
        break
      end
    end
    if ok then
      puddles[#puddles + 1] = {
        x = x, y = y,
        -- 50% larger than original baseline
        w = (3 + r() * 7) * 1.5,
        h = (2 + r() * 2.5) * 1.5,
        a = 0.25 + r() * 0.5,
      }
    end
  end
end

-- Small puddles (GALE): 100 on screen, each lives 2s then teleports.
local smallPuddles = {}
local SMALL_PUDDLES = 100
local SMALL_PUDDLE_LIFE = 2.0
local smallPuddleFrame = -1

local function nowTime()
  local fallback=(State and State.elapsed) or 0
  if Scene and Scene.weatherAnimationTime then
    local ok,v=pcall(Scene.weatherAnimationTime,fallback)
    if ok and type(v)=="number" then return v end
  end
  return fallback
end

local function isGaleWeather()
  local id = tostring(State.id or ""):upper()
  if id == "GALE" then return true end
  -- Soft handoff: still GALE-like if debris+rain heavy and label matches
  if id:find("GALE", 1, true) then return true end
  return false
end

local function randomSmallPos(r)
  return r() * 1.85 - 0.42, r() * 1.85 - 0.42
end

local function initSmallPuddle(i, stagger)
  local r = (love and love.math and love.math.random) or math.random
  local x, y = randomSmallPos(r)
  local t0 = nowTime()
  local age0 = stagger and (r() * SMALL_PUDDLE_LIFE) or 0
  smallPuddles[i] = {
    x = x, y = y,
    w = math.max(2.0, (4 + r() * 8) * 0.35),
    h = math.max(1.4, (2.5 + r() * 3) * 0.35),
    a = 0.50 + r() * 0.40,
    born = t0 - age0,
    expire = t0 - age0 + SMALL_PUDDLE_LIFE,
  }
end

local function seedSmallPuddles()
  for i = 1, SMALL_PUDDLES do
    if not smallPuddles[i] then
      initSmallPuddle(i, true)
    end
  end
end

local function updateSmallPuddles(dt)
  if not isGaleWeather() then
    if smallPuddles[1] then
      for i = 1, SMALL_PUDDLES do smallPuddles[i] = nil end
    end
    return
  end
  -- One update per frame max
  local frame = math.floor(nowTime() * 60)
  if frame == smallPuddleFrame then return end
  smallPuddleFrame = frame

  seedSmallPuddles()
  local t = nowTime()
  local r = (love and love.math and love.math.random) or math.random
  for i = 1, SMALL_PUDDLES do
    local p = smallPuddles[i]
    if not p then
      initSmallPuddle(i, true)
      p = smallPuddles[i]
    end
    if t >= (p.expire or 0) then
      -- Disappear + reappear elsewhere (stagger handled by different expire times)
      local nx, ny = randomSmallPos(r)
      -- Guarantee a different cell-ish position
      if math.abs(nx - p.x) < 0.12 and math.abs(ny - p.y) < 0.12 then
        nx = (nx + 0.35 + r() * 0.5) % 1.85 - 0.42
        ny = (ny + 0.35 + r() * 0.5) % 1.85 - 0.42
      end
      p.x, p.y = nx, ny
      p.w = math.max(2.0, (4 + r() * 8) * 0.35)
      p.h = math.max(1.4, (2.5 + r() * 3) * 0.35)
      p.a = 0.50 + r() * 0.40
      p.born = t
      p.expire = t + SMALL_PUDDLE_LIFE
    end
    -- age for fade (0..1 through life)
    local life = SMALL_PUDDLE_LIFE
    p.age = math.max(0, math.min(life, t - (p.born or t)))
  end
end

local function drawPuddleBatch(list, wetAlpha, x, y, w, h, scale, camX, camY, alpha, lifeFade)
  local px = math.max(0.5, scale or 1)
  for i = 1, #list do
    local p = list[i]
    local lifeA = 1
    if lifeFade and p.age and SMALL_PUDDLE_LIFE then
      local t = p.age / SMALL_PUDDLE_LIFE
      -- Soft in/out so disappear at 1s reads clean
      if t < 0.15 then lifeA = t / 0.15
      elseif t > 0.85 then lifeA = (1 - t) / 0.15
      end
    end
    local sx = x + ((p.x * w) - (camX * px) % (w * 1.5))
    local sy = y + ((p.y * h) - (camY * px) % (h * 1.5))
    if sx > x - 40 and sx < x + w and sy > y - 20 and sy < y + h then
      local wa = wetAlpha * lifeA
      love.graphics.setColor(0.30, 0.36, 0.48, p.a * wa * 0.55 * alpha)
      love.graphics.rectangle("fill", sx, sy, p.w * px, p.h * px)
      love.graphics.setColor(0.75, 0.85, 1.0, p.a * wa * 0.22 * alpha)
      love.graphics.rectangle("fill", sx, sy, math.max(1, p.w * px), math.max(1, math.max(px * 0.35, p.h * px * 0.35)))
    end
  end
end

Draw.wind = 0
Draw.lastDt = 1 / 60

-- ------- the tick

function Draw.update(dt, level)
  Draw.lastDt = dt
  if (level or 0) <= 0 then return end
  Quality.update(dt)

  local ch = Draw.channels()
  local strict3d = strict3dPresent()
  if strict3d and not Draw._wasStrict3d then
    -- Explicit 3D has no 2D fallback. Release flat particle pools/atlas once on
    -- the ownership transition; AUTO intentionally keeps them warm for fail-safe.
    if Particles.suspend then guarded("2d-particles-suspend",Particles.suspend) else Particles.reset() end
  end
  Draw._wasStrict3d=strict3d
  -- The 2D renderer now samples the same world-space wind authority as the 3D
  -- particle engine. Only the screen-X projection is needed by the legacy flat
  -- particle layout; the underlying wind still has full X/Z direction.
  local WE = windEngine()
  if WE and WE.screenX then
    Draw.wind = WE.screenX(52)
  else
    Draw.wind = windAt(nowTime(), ch.gust or 0)
  end

  local vp = Scene.viewport
  if lastRect.w <= 1 and vp then
    lastRect.x, lastRect.y = vp.x, vp.y
    lastRect.w, lastRect.h = vp.w, vp.h
    lastRect.scale = vp.scale
  end
  -- LIGHTNING MUST TICK EVEN WHEN THE 2D LAYER DRAWS NOTHING.
  --
  -- Everything below this point needs a real 2D rect, and `lastRect` is only
  -- populated by Draw.frame -- which returns early, before setting it, whenever
  -- the 2D draw scale is 0. That is precisely the case when the 3D voxel
  -- atmosphere has taken over precipitation: the flat layer draws nothing, so
  -- the rect is never set, so this early return fires every frame, so
  -- Lightning.update() below was NEVER CALLED. No strikes scheduled means no
  -- flash and -- because Audio triggers thunder off Lightning.justStruck -- no
  -- thunder either. That is the reported "thunder and lightning sounds are not
  -- happening", and it only shows up on voxel/first-person setups.
  --
  -- Lightning already falls back to 160x144 and scale 1 when the rect is
  -- unusable, so it does not need the rect. Tick it before the guard.
  do
    local camX = (Scene.now and Scene.now.camX) or 0
    local camY = (Scene.now and Scene.now.camY) or 0
    local lmode = Settings.get("lightning")
    if not Config.visual("lightning") then lmode = "off" end
    local vw = lastRect.w > 1 and lastRect.w or 160
    local vh = lastRect.h > 1 and lastRect.h or 144
    local sc = (lastRect.scale and lastRect.scale > 0) and lastRect.scale or 1
    -- Manual pins use the exact current definition so selecting a non-lightning
    -- weather still kills bolts immediately. Natural AUTO/front handoffs are
    -- different: the synoptic planner deliberately grows/decays the live strike
    -- channel after cloud/wind stages. Feed that live rate only while a staged
    -- handoff is active, so rain -> storm can develop lightning late and storm
    -- -> rain can let electrical activity die out before the rain itself.
    local strikeRate, strikeWeatherId
    local tr = State.synoptic and State.synoptic() or nil
    if State.softTo and type(tr)=="table" and tr.active then
      strikeRate = tonumber(State.ch and State.ch.strike) or 0
      local sourceHas = Types.hasLightning and Types.hasLightning(State.id)
      local targetHas = Types.hasLightning and Types.hasLightning(State.softTo)
      if targetHas and (tonumber(tr.stormU) or 0) > 0.02 then
        strikeWeatherId = State.softTo
      elseif sourceHas then
        strikeWeatherId = State.id
      else
        strikeWeatherId = State.softTo or State.id
      end
    else
      strikeRate = (State.channel and State.channel("strike")) or 0
      local cur=State.current and State.current() or Types.get(State.id)
      strikeWeatherId = cur and cur.id or State.id
    end
    do
      local M=mesoscaleField()
      local ms=M and (not M.ready or M.ready()) and M.peek and M.peek() or nil
      if ms and tonumber(ms.stormScale) then strikeRate=(tonumber(strikeRate) or 0)*tonumber(ms.stormScale) end
    end
    local lightningFrequency = Settings.lightningFrequencyScale and Settings.lightningFrequencyScale() or 1
    strikeRate = (tonumber(strikeRate) or 0) * lightningFrequency
    Lightning.update(dt, strikeRate, lmode, camX, camY, vw, vh, sc, strikeWeatherId)

    -- Flat-renderer NPC lightning is keyed to the scheduler serial rather than
    -- `justStruck` (Audio consumes that flag).  The 3D renderer watches the
    -- same serial independently; only the presentation owner for this frame is
    -- allowed to retarget the visible 2D channel.
    if not strict3d and NpcLightning2D and NpcLightning2D.update then
      guarded("2d-npc-lightning-update", NpcLightning2D.update, dt)
    end
    local serial=tonumber(Lightning.strikeSerial) or 0
    if serial ~= (Draw._lastNpc2dStrikeSerial or 0) then
      Draw._lastNpc2dStrikeSerial=serial
      local n=Scene.now or {}
      local eligible=(lmode=="full") and not use3dLightning()
        and n.visible=="world" and n.outdoor==true and not n.indoors
      if eligible and NpcLightning2D and NpcLightning2D.rollImpact then
        local okImpact,impact=guarded("2d-npc-lightning-roll",NpcLightning2D.rollImpact,camX,camY,vw,vh,nil,lastRect.x,lastRect.y)
        if okImpact and impact and Lightning.retarget
            and Lightning.retarget(impact.hitX,impact.hitY,camX,camY,vw,vh,sc) then
          if NpcLightning2D.hit then guarded("2d-npc-lightning-hit",NpcLightning2D.hit,impact) end
        end
      end
    end
  end

  if lastRect.w <= 1 or lastRect.h <= 1 then return end

  local _, precipitation = Scene.drawScale(Settings)
  if not strict3d then
    Particles.setRect(lastRect.w, lastRect.h, lastRect.scale)
    Particles.spread = Config.get().splashSpread or 1
    local tuning = Config.tuningFor(State.id)
    local splashesOn = precipitation
      and Settings.is("splash", "on") and Config.visual("splashes")
    Particles.update(dt, ch, Quality.budget(tuning.density), Draw.wind,
      Scene.now.camX, Scene.now.camY, splashesOn)
  end

  local mode = Settings.get("lightning")
  if not Config.visual("lightning") then mode = "off" end
  -- (Lightning is ticked above, before the rect guard.)
  -- Tornado.update owns Funnel.update so the 2D relocation event advances
  -- exactly once per frame; this compositor only draws it.

  -- The voxel atmosphere has its own world-space puddles/wetness. Do not run
  -- the flat 2D puddle simulation while explicit 3D owns presentation.
  if strict3d then
    Draw.wet = 0
    if smallPuddles[1] then
      for i = 1, SMALL_PUDDLES do smallPuddles[i] = nil end
    end
  else
    -- Puddles only for whitelist weathers; wetness clears otherwise.
    local allow = Draw.puddleWeather(State.id)
    local rain = math.min(1, ch.rain or 0)
    if allow and rain > 0.02 then
      Draw.wet = math.min(1, Draw.wet + dt * math.max(0.15, rain) * 0.08)
    elseif allow and (State.id == "PSYSTORM" or State.id == "DRAGONSTORM" or State.id == "SLEET") then
      Draw.wet = math.min(1, Draw.wet + dt * 0.04)
    else
      Draw.wet = 0
    end
    updateSmallPuddles(dt)
  end
end

-- ------- the pass

-- `alpha` is the frame's overall strength; `precipitation` is false
-- indoors, where the grade and the lightning survive but nothing falls.
function Draw.pass(x, y, w, h, scale, alpha, precipitation)
  if alpha <= 0 or w <= 1 or h <= 1 then return end
  local ch = Draw.channels()
  local lightMode = Settings.get("lightning")
  if not Config.visual("lightning") then lightMode = "off" end
  -- A healthy 3D lightning pass owns illumination as well as bolt geometry.
  -- Never brighten the whole screen in that case; the localized world-space
  -- light volume is drawn inside the voxel scene instead.
  local flashScale = Settings.lightningFlashScale and Settings.lightningFlashScale() or 1
  local screenScale = Settings.screenEffectsScale and Settings.screenEffectsScale() or 1
  local flash = use3dLightning() and 0 or (Lightning.flash(lightMode) * flashScale * screenScale)

  lastRect.x, lastRect.y, lastRect.w, lastRect.h = x, y, w, h
  lastRect.scale = scale
  Particles.setRect(w, h, scale)
  Particles.camX, Particles.camY = Scene.now.camX, Scene.now.camY

  -- WX PRESENT = 3D is strict once a voxel host is active. The entire flat
  -- Weather FX compositor is bypassed here: weather tint, fog/veil, particles,
  -- psychic wash, glare, 2D puddles, screen-space lightning and funnel. The
  -- separate TIME pipeline is unaffected. Weather state/lightning/audio still
  -- update outside this visual pass, so thunder timing and gameplay continue.
  if strict3dPresent() then
    pcall(function()
      if Audio and Audio.nudgeFromVisual then
        local rainOn = ((ch.rain or 0) + (ch.hail or 0) + (ch.snow or 0)) > 0.02
        local boltOn = (ch.strike or 0) > 0.02 or (Lightning and (Lightning.age or -1) >= 0)
        Audio.nudgeFromVisual(State.id, rainOn, boltOn)
      end
    end)
    return
  end

  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local prevBlend, prevAlphaMode = love.graphics.getBlendMode()

  -- ------- 1. the weather's own grade
  --
  -- The TIME-OF-DAY grade is NOT here.  It used to be, and that was a
  -- design error: it welded a separate feature to the weather pipeline's
  -- ladder, so switching weather off also switched the day/night tint off.
  -- It has its own pipeline now (see main.lua), at a higher priority so it
  -- composites underneath this.
  --
  -- A strike lifts the gloom for as long as it lasts, which is the cue
  -- that sells lightning from inside a building: the room brightens even
  -- though the bolt is not on screen.
  if Config.visual("tint") then
    local sid = State.id
    local sandDust = (sid == "SANDSTORM" or sid == "DUSTSTORM")
    -- Sand/dust: no multiply dim (darkening). Visibility comes from fog/veil haze.
    local dim = sandDust and 0 or math.max(0, ((ch.dim or 0) * alpha - flash * 0.55) * screenScale)
    local cool, warm = ch.cool or 0, (ch.warm or 0) * alpha * screenScale
    -- Sand/dust get their colour from world-anchored banks and grains. A flat
    -- warm multiply, however subtle, is still a camera-sized overlay and works
    -- against the walk-through field illusion.
    if sandDust then warm = 0 end
    if dim > 0.002 or warm > 0.002 then
      local r = 1 - dim * (1.00 + cool * 0.28) + warm * 0.10
      local g = 1 - dim * (1.00 + cool * 0.06) - warm * 0.02
      local b = 1 - dim * (1.00 - cool * 0.48) - warm * 0.16
      love.graphics.setBlendMode("multiply", "premultiplied")
      love.graphics.setColor(math.max(0, math.min(1, r)),
        math.max(0, math.min(1, g)), math.max(0, math.min(1, b)), 1)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setBlendMode("alpha")
    end
  end

  -- ------- 2. fog
  -- FOG INTENSITY OFF → no fog/veil. Also: only fog-family weather (FOG/MIST/…)
  -- may show the 2D fog bank — never on boot CLEAR or non-fog skies.
  local fogOff = Settings.fogOff and Settings.fogOff()
  local fogWeather = State.isFogWeather and State.isFogWeather(State.id)
  -- Sand/dust haze uses same fog/veil path when channels are active.
  if not fogWeather and State.id then
    local sid = State.id
    if sid == "SANDSTORM" or sid == "DUSTSTORM" then
      if (ch.fog or 0) > 0.004 or (ch.veil or 0) > 0.004 then fogWeather = true end
    end
  end
  -- First-person + 3D fog path: never draw the 2D fog overlay.
  -- First-person by itself is NOT proof that 3D fog rendered. Suppress the
  -- 2D safety fog only after the 3D bridge reports an actual mist submission.
  local fpNo2dFog = false
  if use3dFog and use3dFog() then fpNo2dFog = true end
  local fog = (ch.fog or 0) * alpha
  local sid2d = tostring(State.id or ""):upper()
  local sandHaze2d = (sid2d == "SANDSTORM" or sid2d == "DUSTSTORM")
  -- Sandstorm historically had veil but no fog channel, so derive a haze
  -- amount without changing the shared weather channels that feed 3D.
  if sandHaze2d then
    local derived = math.max(ch.fog or 0, (ch.veil or 0) * 0.62, (ch.sand or 0) * 0.28)
    fog = derived * alpha
  end
  -- 4.32.0 (2D only): every ACTIVE haze-family weather now uses the same
  -- wrapping, world-anchored bank representation as sand/dust. This includes
  -- FOG, MIST, SMOG and HAUNTED_MIST. The old viewport fog quad and flat veil
  -- remain only as a compatibility fallback if drawWorldField is unavailable.
  local worldHaze2d = fogWeather and type(Fog.drawWorldField) == "function"
  if fogWeather and not fogOff and not fpNo2dFog and Config.visual("fog")
      and fog > 0.004 and Fog.ready() then
    if Fog.setTint then
      local sid = sid2d
      if sid == "SANDSTORM" then
        Fog.setTint(0.85, 0.72, 0.48, 1, -1)  -- warm suspended sand
      elseif sid == "DUSTSTORM" then
        Fog.setTint(0.78, 0.66, 0.46, 1, -1)  -- darker suspended dust
      elseif sid == "SMOG" then
        Fog.setTint(0.67, 0.70, 0.56, 1, -1)  -- dirty yellow/green pollution haze
      elseif sid == "HAUNTED_MIST" then
        Fog.setTint(0.68, 0.72, 0.88, 1, -1)  -- cold blue-violet spectral mist
      elseif sid == "MIST" then
        Fog.setTint(0.90, 0.93, 0.96, 1, -1)  -- thin pale suspended water
      elseif sid == "FOG" then
        Fog.setTint(0.82, 0.86, 0.91, 1, -1)  -- denser cool fog
      else
        Fog.resetTint()
      end
    end
    love.graphics.push()
    love.graphics.translate(x, y)
    -- Top-down / diorama needs denser banks than first person: the camera
    -- sees the whole map floor, so thin full-screen fog looks absent.
    local topDown = true
    if Settings.isFirstPerson and Settings.isFirstPerson() then topDown = false end

    local fogMul = 1
    if Settings.fogIntensity then fogMul = Settings.fogIntensity() or 1 end
    -- Quality: potato/low (and voxel detail ~75% and under) get a boost so
    -- a single fog layer still reads as weather on the ground.
    local qTier = "high"
    if Quality.tier then
      local okT, tname = pcall(Quality.tier)
      if okT and type(tname) == "string" then qTier = tname end
    end
    local qBoost = 1
    if qTier == "potato" then qBoost = 1.85
    elseif qTier == "low" then qBoost = 1.55
    elseif qTier == "medium" then qBoost = 1.25
    end
    -- Top-down / overhead: 50% less 2D fog so the map stays readable.
    -- First-person fog strength is unchanged.
    if topDown then qBoost = qBoost * 0.675 end  -- was 1.35; -50%

    local fogAlpha = 2.20 + math.min(3.0, fog * 0.55)
    if topDown then fogAlpha = fogAlpha * 0.625 end  -- was 1.25; -50%
    local layers = Quality.budget(1).fogLayers or 1
    if fog > 1.5 then layers = math.max(layers, 3) end
    if fog > 4 then layers = math.max(layers, 4) end
    if fog > 7 then layers = math.max(layers, 5) end
    if topDown then layers = math.max(layers, 1) end
    if topDown and (qTier == "potato" or qTier == "low") then
      layers = math.max(layers, 2)
    end
    layers = math.min(layers, 5)

    local fogAmt = fog * (topDown and 0.575 or 1)  -- was 1.15; -50%
    if worldHaze2d then
      -- All active 2D haze weather is a WORLD FIELD, never a viewport sheet.
      -- Local deterministic banks wrap around the player, keep their world-cell
      -- identities across traversal, and move opposite player/camera travel.
      local worldLayers = (qTier == "potato" or qTier == "low") and 1 or 2
      local fieldAlpha = 0.62
      if sid2d == "MIST" then fieldAlpha = 0.48
      elseif sid2d == "FOG" then fieldAlpha = 0.66
      elseif sid2d == "SMOG" then fieldAlpha = 0.70
      elseif sid2d == "HAUNTED_MIST" then fieldAlpha = 0.60
      end
      -- 4.32.2 (2D only): natural fog-family banks move at half of 4.32.1's
      -- autonomous speed (25% of the pre-4.32.1 rate) while retaining the 3x
      -- bank intensity. Sandstorm/Duststorm keep their existing drift rate.
      local fogFamily = (sid2d == "FOG" or sid2d == "MIST" or sid2d == "SMOG" or sid2d == "HAUNTED_MIST")
      local motionMul = fogFamily and 0.25 or 1.00
      local intensityMul = fogFamily and 3.00 or 1.00

      -- Player parallax comes from ACTUAL player displacement, not raw camera
      -- input. During load stalls Scene.hazeCamera() holds its last coordinate,
      -- while State.elapsed continues so autonomous weather motion never stops.
      local hazeCamX, hazeCamY = Scene.now.camX, Scene.now.camY
      if Scene.hazeCamera then
        local okHC, hx, hy = pcall(Scene.hazeCamera)
        if okHC and type(hx) == "number" and type(hy) == "number" then
          hazeCamX, hazeCamY = hx, hy
        end
      end
      guarded("2d-world-haze:" .. sid2d, Fog.drawWorldField, fogAmt, fogAlpha * fieldAlpha,
        worldLayers, nowTime(), hazeCamX, hazeCamY, scale, w, h,
        ch.fogSpeed or 0.5, motionMul, intensityMul)
    else
      -- Compatibility fallback only. The shipped Fog module always exposes
      -- drawWorldField, but older/third-party replacement modules may not.
      guarded("2d-fog-fallback", Fog.draw, fogAmt, fogAlpha, layers, nowTime(),
        Scene.now.camX, Scene.now.camY, scale, w, h, ch.fogSpeed or 0.5)
      if topDown and Fog.drawGround then
        -- FOG INTENSITY owns fog strength; fixed global INTENSITY must not
        -- leak back in through this compatibility-only ground-fog path.
        local gStrength = fogMul * qBoost * 0.5
        local gLayers = 2
        if qTier == "potato" or qTier == "low" then gLayers = 3 end
        if fogMul >= 2 then gLayers = math.min(3, gLayers + 1) end
        guarded("2d-ground-fog-fallback", Fog.drawGround, fogAmt, fogAlpha * 0.95, gLayers, nowTime(),
          Scene.now.camX, Scene.now.camY, scale, w, h, ch.fogSpeed or 0.5, gStrength)
      end
    end
    love.graphics.pop()
    if Fog.resetTint then Fog.resetTint() end
  end

  -- ------- 3. the veil (fog-family only — same gate as fog bank)
  -- Suppressed in first person / when 3D fog volumes own the haze.
  local veil = (ch.veil or 0) * alpha
  if fogWeather and not fogOff and not fpNo2dFog and Config.visual("veil") and veil > 0.004 then
    -- A world-haze weather must never add a camera-sized veil on top of its
    -- banks; doing so recreates the overlay feel even when the banks themselves
    -- are correctly anchored. Keep the legacy veil only for compatibility if
    -- a replacement Fog module lacks the world-field renderer.
    if not worldHaze2d then
      love.graphics.setBlendMode("alpha")
      local va = math.min(0.95, veil * 0.55 * screenScale)
      local topDownV = true
      if Settings.isFirstPerson and Settings.isFirstPerson() then topDownV = false end
      if topDownV then va = math.min(0.95, va * 0.6) end
      love.graphics.setColor(0.86, 0.88, 0.92, va)
      love.graphics.rectangle("fill", x, y, w, h)
    end
  end

  -- ------- 4. what falls
  -- Every precipitation family owns itself independently. Suppress a 2D
  -- family only after the corresponding 3D pass proves a successful draw.
  -- If (for example) SLEET's rain succeeds but snow fails, rain stays 3D and
  -- only snow falls back to 2D. No blanket FPV shortcut: visibility wins over
  -- assumptions whenever a shader/mesh/host path fails.
  if precipitation and Config.visual("precipitation") and Particles.ready() then
    local drawCh = filtered2dPrecipChannels(ch)
    local has = (drawCh.rain or 0) + (drawCh.snow or 0) + (drawCh.sand or 0)
        + (drawCh.ash or 0) + (drawCh.debris or 0) + (drawCh.hail or 0)
    if has > 0.01 then
      love.graphics.push()
      love.graphics.translate(x, y)
      guarded("2d-precip", Particles.draw, alpha, drawCh)
      love.graphics.pop()
    end
  end

  -- Keep SFX locked to what is on screen
  pcall(function()
    if Audio and Audio.nudgeFromVisual then
      -- Snow counts as precipitation on screen. This was rain+hail only, so a
      -- SNOW-ONLY storm -- THUNDERSNOW is the one that matters, it has no rain
      -- or hail channel whatsoever -- reported "nothing falling" on every frame
      -- and had its audio stopped continuously.
      local rainOn = ((ch.rain or 0) + (ch.hail or 0) + (ch.snow or 0)) > 0.02
      local boltOn = (ch.strike or 0) > 0.02 or (Lightning and (Lightning.age or -1) >= 0)
      Audio.nudgeFromVisual(State.id, rainOn, boltOn)
    end
  end)


  -- ------- 4b. the psychic wash
  --
  -- ADDITIVE, not a multiply like every other tint in this pass: a
  -- psystorm's sky glows violet rather than being darkened toward it, and
  -- a multiply can only ever take light away.  Drawn after the
  -- precipitation so the rain glows too, which is what makes it read as
  -- the air itself being lit rather than a filter over the picture.
  local psy = (ch.psy or 0) * alpha * screenScale
  if Config.visual("tint") and psy > 0.004 then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.42, 0.10, 0.55, math.min(0.6, psy * 0.42))
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setBlendMode("alpha")
  end

  -- ------- 5. glare
  local glare = (ch.glare or 0) * alpha * screenScale
  if Config.visual("glare") and glare > 0.004 then
    love.graphics.setBlendMode("add")
    guarded("2d-glare", glareMesh, x, y, w, h, math.min(0.5, glare * 0.34), math.min(0.28, glare * 0.16))
    love.graphics.setBlendMode("alpha")
  end

  -- ------- 6b. puddles
  --
  -- Under the falling water and over the world, because a puddle is ON the
  -- ground: drawn after the grade so it darkens with the sky, and before
  -- the funnel, which is not weather.
  if Config.visual("puddles") ~= false then
    local camX, camY = Scene.now.camX, Scene.now.camY
    love.graphics.setBlendMode("alpha")
    -- Full puddles: rain-family whitelist
    local puddleScale = Settings.puddleAmountScale and Settings.puddleAmountScale() or 1
    local visibleWet = Draw.wet * puddleScale
    if precipitation and visibleWet > 0.02 and Draw.puddleWeather(State.id) then
      seedPuddles()
      guarded("2d-puddles", drawPuddleBatch, puddles, visibleWet, x, y, w, h, scale, camX, camY, alpha)
    end
    -- GALE: no splash / small-puddle ground flecks (leaves/debris only)
  end

  -- ------- 6. lightning
  --
  -- A roused bird lends the strike its colour, so a Zapdos storm is not
  -- merely a storm that happens to contain a Zapdos.
  Lightning.tint = Legendary.boltTint()
  do
    local camX = (Scene.now and Scene.now.camX) or 0
    local camY = (Scene.now and Scene.now.camY) or 0
    -- A healthy 3D lightning pass owns BOTH the bolt and its illumination.
    -- Do not leave the old full-screen flash active underneath a world-space
    -- strike: that would turn the lighting back into a camera overlay. If the
    -- 3D pass is unhealthy, this fails open to the proven 2D fallback. Indoors
    -- remain flash-only because there is no outdoor world bolt to render.
    local drawBolt = not use3dLightning() and not (Scene.now and Scene.now.indoors)
    if not use3dLightning() then
      -- Redraw the struck actor first so the physical channel terminates on top
      -- of the charred/skeleton reaction.  Smoke is part of the same world-
      -- anchored reaction and remains for the full configured three seconds.
      if NpcLightning2D and NpcLightning2D.draw then
        guarded("2d-npc-lightning-draw",NpcLightning2D.draw,x,y,w,h,camX,camY)
      end
      guarded("2d-lightning", Lightning.draw, x, y, w, h, alpha, lightMode, drawBolt, camX, camY, flashScale * screenScale)
    end
  end

  -- ------- 7. the tornado funnel, over the finished weather frame
  --
  -- Funnel is a world event, not precipitation.  It must render from the
  -- normal full-frame compositor so it is visible even when no text box is
  -- open.  Keeping it out of passPrecipitationOnly() also prevents dialog
  -- clipping from drawing a second, partially clipped funnel.
  guarded("tornado-funnel", Funnel.draw, x, y, w, h, scale)

  love.graphics.setBlendMode(prevBlend, prevAlphaMode)
  love.graphics.setColor(prevR, prevG, prevB, prevA)
end

-- ------- clipping
--
-- Two scissors, not one.  The outer one keeps weather inside the playfield
-- so it never falls in the letterbox bars.  The inner one -- only on the
-- flat renderer, and only while a dialog box is open -- keeps the FALLING
-- part above the box, so rain lands behind the text instead of on it.
--
-- The rect the particles are SIMULATED in does not change when a box
-- opens; only the visible region does.  Changing the field would rescale
-- every particle twice per conversation.

local function textBoxRect(x, y, w, h)
  if not Config.visual("textBoxClear") then return nil end
  local box = Scene.now.textBox
  if not box then return nil end
  local bx = x + (tonumber(box.x) or 0) / 160 * w
  local by = y + (tonumber(box.y) or 0) / 144 * h
  local bw = (tonumber(box.w) or 160) / 160 * w
  local bh = (tonumber(box.h) or 0) / 144 * h
  local x2,y2=x+w,y+h
  bx=math.max(x,math.min(x2,bx)); by=math.max(y,math.min(y2,by))
  bw=math.max(0,math.min(x2-bx,bw)); bh=math.max(0,math.min(y2-by,bh))
  if bw<=0 or bh<=0 then return nil end
  return {x=bx,y=by,w=bw,h=bh}
end

-- Run a draw callback in the non-overlapping parts of the playfield that are
-- not occupied by the current dialogue/route banner. This keeps the world
-- alive behind 2D UI without painting weather or colour grading over the text.
local function drawOutsideTextBox(x,y,w,h,fn)
  local box=textBoxRect(x,y,w,h)
  if not box then fn(); return true end
  local x2,y2=x+w,y+h
  local bx2,by2=box.x+box.w,box.y+box.h
  local regions={
    {x,y,w,math.max(0,box.y-y)},
    {x,by2,w,math.max(0,y2-by2)},
    {x,box.y,math.max(0,box.x-x),box.h},
    {bx2,box.y,math.max(0,x2-bx2),box.h},
  }
  local drew=false
  for i=1,#regions do
    local r=regions[i]
    if r[3]>0.5 and r[4]>0.5 then
      love.graphics.setScissor(r[1],r[2],r[3],r[4])
      fn()
      drew=true
    end
  end
  return drew
end

function Draw.frame(x, y, w, h, scale, allowTextBoxCut)
  local alpha, precipitation = Scene.drawScale(Settings)
  if alpha <= 0 then return false end

  local sx, sy, sw, sh = love.graphics.getScissor()
  local ok, err
  local now=Scene.now

  -- Flat present occurs after the native textbox/banner has already been
  -- painted. Draw the weather only in the uncovered world regions instead of
  -- suppressing the entire effect (old pop-out bug) or covering the UI.
  if allowTextBoxCut and now and now.textBox and Config.visual("textBoxClear") then
    ok,err=pcall(function()
      drawOutsideTextBox(x,y,w,h,function()
        Draw.pass(x,y,w,h,scale,alpha,precipitation)
      end)
    end)
  else
    love.graphics.setScissor(x, y, w, h)
    ok, err = pcall(Draw.pass, x, y, w, h, scale, alpha, precipitation)
  end

  if sx then
    love.graphics.setScissor(sx, sy, sw, sh)
  else
    love.graphics.setScissor()
  end
  if not ok then error(err, 0) end   -- let the engine retire the pipeline
  return true
end

-- Apply the standalone time grade without tinting a dialogue/banner that was
-- already drawn into the flat frame. World-present renderers do not need this
-- helper because their UI is composed after the world canvas.
function Draw.gradeFrame(x,y,w,h,indoors,protectTextBox)
  if not protectTextBox or not (Scene.now and Scene.now.textBox) or not Config.visual("textBoxClear") then
    return Draw.grade(x,y,w,h,indoors)
  end
  local sx,sy,sw,sh=love.graphics.getScissor()
  local any=false
  local ok,err=pcall(function()
    any=drawOutsideTextBox(x,y,w,h,function()
      if Draw.grade(x,y,w,h,indoors) then any=true end
    end) or any
  end)
  if sx then love.graphics.setScissor(sx,sy,sw,sh) else love.graphics.setScissor() end
  if not ok then error(err,0) end
  return any
end

-- The precipitation layer on its own, for the clipped second pass.
function Draw.passPrecipitationOnly(x, y, w, h, scale, alpha)
  if strict3dPresent() then return end
  -- This function's comment used to claim it skipped the 2D pass when the 3D
  -- bridge was drawing world-space precipitation. IT NEVER DID -- it handed
  -- Draw.channels() straight to Particles.draw with no ownership check at all.
  -- Draw.pass has the full gating (use3dPrecip, the FPV snow branch); this
  -- parallel path had none, so on the diorama route the 2D snow sheet drew over
  -- the 3D flakes and read as an overlay locked to the screen.
  --
  -- Same ownership rules as Draw.pass, so the two paths cannot disagree.
  if not (Config.visual("precipitation") and Particles.ready()) then return end
  local drawCh = filtered2dPrecipChannels(Draw.channels())
  local has = (drawCh.rain or 0) + (drawCh.snow or 0) + (drawCh.sand or 0)
      + (drawCh.ash or 0) + (drawCh.debris or 0) + (drawCh.hail or 0)
  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
  -- Same per-family rule on the diorama path -- this is the route a
  -- voxel/first-person setup actually takes, so it must never drift from pass().
  if has > 0.01 then
    love.graphics.push()
    love.graphics.translate(x, y)
    guarded("2d-precip-clipped", Particles.draw, alpha, drawCh)
    love.graphics.pop()
  end
  -- Funnel deliberately does not draw here.  This pass is precipitation-only
  -- and may be clipped above a text box; the full-frame pass owns the tornado
  -- exactly once per frame.

  love.graphics.setBlendMode(prevBlend, prevAlphaMode)
  love.graphics.setColor(prevR, prevG, prevB, prevA)
end

-- THE TIME-OF-DAY GRADE, on its own.
--
-- Its own pass, called by its own pipeline, so it survives the weather
-- being switched off entirely.  A multiply for the colour of the light and
-- an add to put a little back into the shadows -- an add is what stops a
-- night grade reading as "the brightness control is broken".
--
-- Returns true if it drew, which the pipeline's stage handshake needs.
function Draw.grade(x, y, w, h, indoors)
  local mr, mg, mb, ar, ag, ab = TOD.grade(indoors)
  if not mr then return false end
  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(mr, mg, mb, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  if ar > 0.001 or ag > 0.001 or ab > 0.001 then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(ar, ag, ab, 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end
  love.graphics.setBlendMode(prevBlend, prevAlphaMode)
  love.graphics.setColor(prevR, prevG, prevB, prevA)
  return true
end

function Draw.npcLightningActive()
  return NpcLightning2D and NpcLightning2D.activeCount and NpcLightning2D.activeCount()>0 or false
end

function Draw.invalidate()
  glare.mesh = nil
  puddles = {}
  smallPuddles = {}  -- reseed with new sizes
  Particles.invalidate()
  Fog.invalidate()
  Lightning.reset()
  -- Lightning.reset intentionally preserves the monotonically increasing
  -- strikeSerial used by audio/3D observers.  A renderer invalidate must
  -- acknowledge that existing serial rather than resetting our observer to
  -- zero, or the first post-resize frame can mistake an OLD strike for a new
  -- NPC impact.
  Draw._lastNpc2dStrikeSerial=tonumber(Lightning.strikeSerial) or 0
  if NpcLightning2D and NpcLightning2D.invalidate then guarded("2d-npc-lightning-invalidate",NpcLightning2D.invalidate) end
  lastRect.w, lastRect.h = 0, 0
end

return Draw
