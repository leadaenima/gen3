-- ============================================================================
-- WEATHER FX WIND ENGINE
-- ============================================================================
-- One world-space wind authority for every weather presentation path.
--
-- Goals:
--   * never camera-relative;
--   * one shared direction for rain/snow/grains/fog/clouds/audio;
--   * slow veer/backing instead of a permanently fixed vector;
--   * weather-specific sustained flow, gusts and lulls;
--   * continuous integrated advection so changing direction cannot teleport
--     clouds/fog by multiplying a new vector by a large global time value.
--
-- This is presentation physics only. It does not alter player movement.

local Wind = {}

local sin, cos, pi, exp, sqrt = math.sin, math.cos, math.pi, math.exp, math.sqrt
local TWO_PI = pi * 2

local function clamp(v, lo, hi)
  v = tonumber(v) or 0
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function wrapPi(a)
  a = (tonumber(a) or 0) % TWO_PI
  if a > pi then a = a - TWO_PI end
  return a
end

local function angleDelta(a, b)
  return wrapPi((tonumber(b) or 0) - (tonumber(a) or 0))
end

-- Tiny deterministic PRNG. Avoid Lua 5.3 bitwise operators so LuaJIT/5.1 hosts
-- remain supported.
local rngState = 971731
local function rand01()
  rngState = (rngState * 48271) % 2147483647
  return rngState / 2147483647
end
local function randRange(a, b)
  return a + (b - a) * rand01()
end

-- Numbers are deliberately descriptive rather than meteorological units.
-- speed controls precipitation lean; advect controls long-lived cloud motion.
-- floor is the minimum long-wave envelope: light weather can almost stop,
-- severe weather remains physically sustained.
local PROFILES = {
  calm      = { speed={0.00,0.10}, floor=0.00, gust=0.20, turn=1.00, dir={22,48}, str={10,25}, response=5.0, advect=0.10, sway=0.16 },
  breeze    = { speed={0.10,0.32}, floor=0.05, gust=0.30, turn=0.90, dir={20,42}, str={8,20},  response=4.0, advect=0.24, sway=0.14 },
  rain      = { speed={0.22,0.58}, floor=0.14, gust=0.40, turn=0.75, dir={18,38}, str={7,17},  response=3.2, advect=0.36, sway=0.12 },
  storm     = { speed={0.48,1.00}, floor=0.34, gust=0.62, turn=1.20, dir={11,26}, str={4,11},  response=2.1, advect=0.58, sway=0.18 },
  psychic   = { speed={0.46,1.10}, floor=0.24, gust=0.78, turn=1.75, dir={7,18},  str={3,9},   response=1.8, advect=0.64, sway=0.26 },
  snow      = { speed={0.16,0.50}, floor=0.10, gust=0.42, turn=0.90, dir={18,40}, str={7,18},  response=3.8, advect=0.30, sway=0.18 },
  blizzard  = { speed={0.58,1.18}, floor=0.48, gust=0.66, turn=1.00, dir={12,28}, str={4,11},  response=2.2, advect=0.62, sway=0.17 },
  gale      = { speed={0.70,1.30}, floor=0.58, gust=0.56, turn=0.85, dir={14,30}, str={4,10},  response=2.0, advect=0.74, sway=0.13 },
  sand      = { speed={0.72,1.28}, floor=0.64, gust=0.48, turn=0.52, dir={18,42}, str={5,13},  response=2.5, advect=0.70, sway=0.08 },
  ash       = { speed={0.12,0.42}, floor=0.10, gust=0.34, turn=1.05, dir={20,44}, str={8,20},  response=4.2, advect=0.26, sway=0.17 },
}

local function classify(id, gust)
  id = tostring(id or ""):upper()
  if id == "PSYSTORM" or id == "PSY" then return "psychic" end
  if id == "SANDSTORM" or id == "DUSTSTORM" then return "sand" end
  if id == "BLIZZARD" or id == "WHITEOUT" or id == "THUNDERSNOW" or id == "TSNOW" then return "blizzard" end
  if id == "GALE" or id == "STRONG_WINDS" or id == "BRAWL_WIND" or id == "FLOCKSTORM" then return "gale" end
  if id == "STORM" or id == "DRAGONSTORM" or id == "HEAVY_RAIN" or id == "PRIMAL_RAIN" then return "storm" end
  if id:find("SNOW", 1, true) or id == "SLEET" or id == "HAIL" then return "snow" end
  if id == "ASHFALL" or id == "BLACK_ASH" then return "ash" end
  if id == "RAIN" or id == "RAIN_HEAVY" or id == "DRIZZLE" then return "rain" end
  gust = tonumber(gust) or 0
  if gust >= 0.80 then return "gale" end
  if gust >= 0.25 then return "breeze" end
  return "calm"
end

local S = {
  id = "",
  profileKey = "calm",
  angle = 0.37,
  targetAngle = 0.37,
  base = 0,
  targetBase = 0,
  dirTimer = 0,
  strengthTimer = 0,
  phase = 0,
  phase2 = 1.9,
  x = 0,
  z = 0,
  strength = 0,
  envelope = 0,
  advectX = 0,
  advectZ = 0,
  audio = 0,
  pitch = 1,
  serial = 0,
}

local function chooseDirection(p, changed)
  local maxTurn = tonumber(p.turn) or 0.8
  -- A weather change may establish a new prevailing flow, but never snaps to it.
  local extra = changed and 0.45 or 0
  S.targetAngle = wrapPi(S.angle + randRange(-(maxTurn + extra), maxTurn + extra))
  S.dirTimer = randRange(p.dir[1], p.dir[2])
end

local function chooseStrength(p, gust)
  local lo, hi = p.speed[1], p.speed[2]
  local g = clamp(gust, 0, 1.4)
  -- Catalogue gust remains the authority for how windy a weather is. Profiles
  -- describe its *character*. A non-windy weather therefore cannot gain a gale
  -- merely because this procedural engine exists.
  local scale = 0.18 + 0.82 * clamp(g, 0, 1)
  if g <= 0.02 and S.profileKey == "calm" then scale = 0 end
  S.targetBase = randRange(lo, hi) * scale
  S.strengthTimer = randRange(p.str[1], p.str[2])
end

function Wind.update(dt, state)
  dt = math.max(0, tonumber(dt) or 0)
  -- Cap response integration over hitches/map loads. Advection still advances
  -- only by this capped physical step so a loading pause cannot fling clouds.
  local step = math.min(dt, 0.20)

  local id, gust = "", 0
  local profileId = nil
  if type(state) == "table" then
    id = tostring(state.id or "")
    local ch = state.ch
    if type(ch) == "table" then gust = tonumber(ch.gust) or 0 end
    if gust == 0 and state.current then
      local ok, def = pcall(state.current)
      if ok and type(def) == "table" and type(def.ch) == "table" then gust = tonumber(def.ch.gust) or 0 end
    end
    -- Natural handoffs stage wind independently from precipitation. Once the
    -- planner's wind front has actually begun, adopt the target weather's wind
    -- *character* while continuing to use the live eased gust amount. Base
    -- strength/direction still approach smoothly and cloud advection is
    -- integrated, so this cannot teleport a cloud bank. At final State.id
    -- commit the engine is already on the target profile: no last-frame gust.
    if state.softTo and state.synoptic then
      local tr=state.synoptic()
      if type(tr)=="table" and tr.active and (tonumber(tr.windU) or 0) > 0.02 then
        profileId=tostring(state.softTo or "")
      end
    end
  else
    id = tostring(state or "")
  end

  profileId = profileId or id
  local key = classify(profileId, gust)
  local p = PROFILES[key] or PROFILES.breeze
  local changed = profileId ~= S.id or key ~= S.profileKey
  if changed then
    S.id, S.profileKey = profileId, key
    S.serial = S.serial + 1
    chooseDirection(p, true)
    chooseStrength(p, gust)
  end

  S.dirTimer = S.dirTimer - dt
  S.strengthTimer = S.strengthTimer - dt
  if S.dirTimer <= 0 then chooseDirection(p, false) end
  if S.strengthTimer <= 0 then chooseStrength(p, gust) end

  local turnResponse = math.max(1.0, tonumber(p.response) or 3)
  local a = 1 - exp(-step / turnResponse)
  S.angle = wrapPi(S.angle + angleDelta(S.angle, S.targetAngle) * a)
  S.base = S.base + (S.targetBase - S.base) * a

  -- Long respiration creates genuine lulls; faster secondary wave makes gust
  -- shoulders. Both phases are continuous across target changes.
  S.phase = S.phase + step * (0.22 + (p.gust or 0.3) * 0.12)
  S.phase2 = S.phase2 + step * (0.57 + (p.gust or 0.3) * 0.18)
  local longWave = 0.5 + 0.5 * sin(S.phase)
  longWave = longWave * longWave * (3 - 2 * longWave)
  local smallWave = 0.5 + 0.5 * sin(S.phase2 + sin(S.phase * 0.31) * 0.8)
  local floorEnv = clamp(p.floor or 0.1, 0, 0.95)
  local envelope = floorEnv + (1 - floorEnv) * longWave
  envelope = envelope * (0.78 + (p.gust or 0.3) * 0.34 * smallWave)
  S.envelope = clamp(envelope, 0, 1.35)

  local micro = sin(S.phase * 0.43 + S.phase2 * 0.17) * (p.sway or 0.12)
  local angle = wrapPi(S.angle + micro)
  S.strength = math.max(0, S.base * S.envelope)
  S.x = cos(angle) * S.strength
  S.z = sin(angle) * S.strength

  -- Integrated world displacement: cloud/fog code consumes this rather than
  -- currentVector * globalTime, which would jump whenever direction changes.
  local advect = tonumber(p.advect) or 0.3
  S.advectX = S.advectX + cos(angle) * advect * S.envelope * step
  S.advectZ = S.advectZ + sin(angle) * advect * S.envelope * step

  local hi = math.max(0.01, tonumber(p.speed[2]) or 1)
  S.audio = clamp(S.strength / hi, 0, 1)
  S.pitch = clamp(0.88 + S.audio * 0.16 + smallWave * 0.025, 0.82, 1.08)
  return S
end

-- Zero-allocation live state for internal render/audio hot paths. Callers must
-- treat this as read-only. `state()` remains the snapshot API for tests/debug
-- and external code that may retain a table across updates.
function Wind.peek()
  return S
end

function Wind.state()
  return {
    id=S.id, profile=S.profileKey, angle=S.angle,
    x=S.x, z=S.z, strength=S.strength, envelope=S.envelope,
    advectX=S.advectX, advectZ=S.advectZ,
    audio=S.audio, pitch=S.pitch, serial=S.serial,
  }
end

function Wind.vector(scale)
  scale = tonumber(scale) or 1
  return S.x * scale, S.z * scale
end

function Wind.direction()
  local l = sqrt(S.x*S.x + S.z*S.z)
  if l < 1e-6 then return cos(S.angle), sin(S.angle) end
  return S.x/l, S.z/l
end

function Wind.screenX(pxPerSecond)
  return S.x * (tonumber(pxPerSecond) or 52)
end

function Wind.profileFor(id, gust)
  local k = classify(id, gust)
  return k, PROFILES[k]
end

function Wind._reset(seed)
  rngState = tonumber(seed) or 971731
  S.id, S.profileKey = "", "calm"
  S.angle, S.targetAngle = 0.37, 0.37
  S.base, S.targetBase = 0, 0
  S.dirTimer, S.strengthTimer = 0, 0
  S.phase, S.phase2 = 0, 1.9
  S.x, S.z, S.strength, S.envelope = 0, 0, 0, 0
  S.advectX, S.advectZ = 0, 0
  S.audio, S.pitch, S.serial = 0, 1, 0
end

return Wind
