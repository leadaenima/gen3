-- TIME OF DAY: a clock, a Gold/Silver/Crystal colour grade, and the
-- engine's `world.tod` answer.
--
-- WHY THIS MOD OWNS A CLOCK AT ALL.  Version 1 borrowed Dramatic Shape's,
-- which meant that without that mod installed there was no night, and
-- "fog is likelier after dark" was dead code.  A weather system with no
-- clock is half a weather system, so this one carries its own -- and
-- still defers to Dramatic Shape when that mod is present, because two
-- clocks disagreeing about what time it is would be worse than either.
--
-- FOUR SOURCES, chosen in config.lua under `time.source`:
--
--   auto    Dramatic Shape's clock if that mod is loaded, else `cycle`.
--           The default, and the only one that needs no decision.
--   system  the device's real clock, which is what GSC actually did --
--           play at night and it is night.
--   cycle   this mod's own accelerated day, `cycleMinutes` long.
--   fixed   pinned to one phase, for screenshots and for players who
--           want the look without the schedule.
--   off     no clock, no grade, no world.tod.  Vanilla lighting.
--
-- THE PHASES are GSC's, plus one.  Gold and Silver shipped three palette
-- sets -- morning, day and night -- and Crystal kept them.  This adds EVE
-- between day and night, because the interesting half of a sunset is the
-- half GSC had no palette for, and because the grade here is a continuous
-- blend rather than three fixed palettes, so a fourth costs one table row.
-- `world.tod` publishes all four; the engine treats the value as opaque
-- and hands it to `map.palette` for palette mods to key off, so a mod that
-- only knows MORN/DAY/NITE simply never matches EVE and falls through to
-- its default -- which is the correct behaviour, not a bug.
--
-- THE GRADE IS A MULTIPLY PLUS AN ADD, not a palette swap.  A palette swap
-- is what the hardware did and would be more faithful, but it needs a
-- second full set of palettes authored per map per colour mode, and it
-- would fight every other palette mod for the same registry.  A grade over
-- the finished world costs one rectangle, works identically in every
-- colour mode the engine offers (mono, SGB, GBC, OG RED), rides through
-- GBC FX because that runs after it, and composes with weather because it
-- is drawn in the same pass by the same compositor.

local V = ...
local mod = V.mod
local Config = V.require("Config")
local Interop = V.require("Interop")

local TOD = {}

-- ------- phases
--
-- `at` is the hour the phase is fully itself; the grade blends between
-- neighbours, so these are anchors rather than boundaries.  Ordering is
-- circular: NITE wraps past midnight to MORN.
--
--   mul   multiplied over the frame -- what darkens and colours it
--   add   added after -- a little light back into the shadows, which is
--         what stops a night grade reading as "the brightness is broken"
--
-- The values are tuned against GSC's own palettes rather than invented:
-- morning is a warm lift, day is exactly neutral (so DAY costs nothing at
-- all -- see `active`), evening is amber with the blue pulled down, and
-- night is the blue-violet GSC used, which darkens far less than it
-- recolours.  A night you cannot read the map through is not authentic,
-- it is just dark.

-- Morning and evening were far too timid in 2.1.x: at 09:00 the blend sat
-- around a 0.97 green and a 0.91 blue, which is under the noise floor of a
-- handheld LCD photographed in a lit room -- indistinguishable from "not
-- working".  GSC's morning palette is a genuinely visible warm shift, so
-- these now are too.  DAY stays EXACTLY neutral, which is what lets the
-- grade cost nothing at noon.
TOD.PHASES = {
  { id = "NITE", at = 1.0,  mul = { 0.52, 0.55, 0.85 }, add = { 0.00, 0.01, 0.07 } },
  { id = "MORN", at = 7.0,  mul = { 1.00, 0.90, 0.74 }, add = { 0.08, 0.04, 0.00 } },
  { id = "DAY",  at = 13.0, mul = { 1.00, 1.00, 1.00 }, add = { 0.00, 0.00, 0.00 } },
  { id = "EVE",  at = 19.0, mul = { 1.00, 0.74, 0.58 }, add = { 0.10, 0.03, 0.00 } },
  { id = "NITE", at = 22.5, mul = { 0.52, 0.55, 0.85 }, add = { 0.00, 0.01, 0.07 } },
}

-- nil = follow the clock; a phase string pins Weather FX to that phase.
TOD.pin = nil
-- A voxel host may own the *clock source* and screen grade, but Weather FX still
-- simulates astronomy from that clock.  This avoids two competing clocks while
-- allowing the celestial engine to drive physical sun/moon/light state.
TOD._forceOffByHost = false -- legacy alias: now means host owns screen grade, not time
TOD._hostOwnsGrade = false

-- The phase NAME for a given hour.  Boundaries, not anchors: this is what
-- `world.tod` publishes, and a hook answer has to be a step function even
-- though the grade is continuous.
function TOD.phaseAt(hour)
  hour=(tonumber(hour) or 13)%24
  local ok,Sim=pcall(V.require,"CelestialSim")
  if ok and Sim and Sim.sample then
    local ok2,st=pcall(Sim.sample,hour)
    if ok2 and st then
      local rise,set=st.sunrise or 6,st.sunset or 18
      local function dist(a,b) return (a-b+24)%24 end
      if hour>=rise-1.25 and hour<rise+3.0 then return "MORN" end
      if hour>=set-2.0 and hour<set+1.25 then return "EVE" end
      if st.sun and st.sun.altitudeDeg and st.sun.altitudeDeg>=-4 then return "DAY" end
      return "NITE"
    end
  end
  if hour>=4 and hour<10 then return "MORN" end
  if hour>=10 and hour<17 then return "DAY" end
  if hour>=17 and hour<20 then return "EVE" end
  return "NITE"
end

-- ------- the clock

TOD.elapsed = 0          -- seconds the cycle source has run
TOD.hour = 13            -- 0..24, the live answer
TOD.tod = "DAY"          -- the published phase
TOD.source = "none"      -- what actually answered, for the debug row
TOD.hostMode = nil       -- explicit voxel-host pin: day/night/dusk/dawn/cycle/sync

-- Monotonic in-game day coordinate for systems that need a real day count
-- rather than the season-scaled year index. The lunar clock consumes this so
-- one observed game day == one lunar day even when a season is only 15 days.
TOD.gameDays = 0
TOD._trackedDayCount = 0
TOD._trackedDayHour = nil
TOD._trackedDaySource = nil
TOD._cycleOffset = nil       -- phase offset that makes source/day-length edits continuous
TOD._lastCyclePeriod = nil
TOD._lastEffectiveSource = nil

local function trackGameDay(hour, source, period)
  hour=(tonumber(hour) or 0)%24
  source=tostring(source or "none")
  if source=="system" then
    -- CelestialSim uses the actual calendar directly for SYSTEM time.
    TOD.gameDays=nil
  elseif source=="fixed" or source=="pinned" or source=="off" then
    if type(TOD.gameDays)~="number" then TOD.gameDays=TOD._trackedDayCount+hour/24 end
  else
    -- CYCLE and voxel-host clocks both expose a visible hour. Count actual
    -- midnight crossings instead of deriving the day from cycleMinutes; this
    -- keeps lunar/season day serials continuous when the player edits day length.
    local prev=TOD._trackedDayHour
    if TOD._trackedDaySource==source and type(prev)=="number" and (prev-hour)>12 then
      TOD._trackedDayCount=TOD._trackedDayCount+1
    end
    TOD.gameDays=TOD._trackedDayCount+hour/24
  end
  TOD._trackedDayHour=hour
  TOD._trackedDaySource=source
end

function TOD.gameDaySerial()
  return tonumber(TOD.gameDays) or 0
end

function TOD.persist()
  pcall(function()
    mod.save:set("todElapsed", tonumber(TOD.elapsed) or 0)
    mod.save:set("todHour", tonumber(TOD.hour) or 13)
    mod.save:set("todTrackedDayCount", tonumber(TOD._trackedDayCount) or 0)
    mod.save:set("todTrackedDayHour", tonumber(TOD._trackedDayHour) or -1)
    mod.save:set("todTrackedDaySource", tostring(TOD._trackedDaySource or ""))
  end)
end

local function resetPersistedClockDefaults()
  TOD.elapsed=0
  TOD.hour=13
  TOD.tod=TOD.phaseAt(TOD.hour)
  TOD.gameDays=TOD.hour/24
  TOD._trackedDayCount=0
  TOD._trackedDayHour=nil
  TOD._trackedDaySource=nil
end

function TOD.restore()
  local ok=pcall(function()
    -- Old saves legitimately have no Weather FX clock keys.  Never use the
    -- current process state as their default: loading another save in the same
    -- emulator session would otherwise leak the previous save's hour/day into it.
    local rawElapsed=mod.save:get("todElapsed",nil)
    local rawHour=mod.save:get("todHour",nil)
    if rawElapsed==nil and rawHour==nil then
      resetPersistedClockDefaults()
      return
    end
    TOD.elapsed=math.max(0,tonumber(rawElapsed) or 0)
    TOD.hour=(tonumber(rawHour) or 13)%24
    TOD.tod=TOD.phaseAt(TOD.hour)
    TOD._trackedDayCount=math.max(0,math.floor(tonumber(mod.save:get("todTrackedDayCount",0)) or 0))
    local h=tonumber(mod.save:get("todTrackedDayHour",-1))
    TOD._trackedDayHour=(h and h>=0) and (h%24) or nil
    local src=mod.save:get("todTrackedDaySource","")
    TOD._trackedDaySource=(type(src)=="string" and src~="") and src or nil
    TOD.gameDays=TOD._trackedDayCount+TOD.hour/24
  end)
  if not ok then resetPersistedClockDefaults() end
  -- Force a phase rebase on the next cycle frame so the restored visible hour
  -- remains continuous regardless of source/day-length settings.
  TOD._cycleOffset=nil
  TOD._lastCyclePeriod=nil
  TOD._lastEffectiveSource=nil
end

local ds = { tried = false, DayNight = nil, broken = false }

-- Live mod-menu authority. TIME OF DAY is a user-facing switch, not merely an
-- AUTO-weather bias toggle: OFF must stop Weather FX's own clock/grade too.
-- Resolve Settings lazily to avoid a module-load cycle (Settings itself can
-- consult WeatherState, which consults TimeOfDay later in the boot).
local function menuDaytimeOn()
  local on = true
  pcall(function()
    local S = V.require("Settings")
    if S and S.get then on = S.get("daytime") ~= "off" end
  end)
  return on
end

-- Dramatic Shape's DayNight module, or nil.  Resolved LAZILY, on first
-- use rather than at load: a handle taken at load could be taken before
-- that mod's entry chunk assigned its exports on some load orderings, and
-- a nil cached then would be a nil forever.  Re-probed while the answer is
-- nil, never after a failure.
local function dayNight()
  if ds.broken or not Config.get().time then return nil end
  if ds.DayNight then return ds.DayNight end
  -- Either fork of the voxel diorama; lib/Interop.lua knows the family and
  -- shape-checks the module, so a fork that renamed it costs a lighting
  -- nuance rather than a crash.
  local ok, module, id = pcall(Interop.dayNight)
  if not ok then
    ds.broken = true
    mod.log:warn("voxel clock probe failed (%s); using this mod's own",
      tostring(module))
    return nil
  end
  if not module then return nil end
  ds.DayNight = module
  ds.id = id
  return module
end

function TOD.voxelClockAvailable()
  return dayNight() ~= nil
end

local FIXED_HOUR = { MORN = 7, DAY = 13, EVE = 19, NITE = 1 }

local function hostModeOf(dn)
  if not dn then return nil end
  local mode=nil
  pcall(function()
    if dn.setting and type(dn.setting.get)=="function" then mode=dn.setting:get()
    elseif type(dn.mode)=="function" then mode=dn.mode() end
  end)
  if type(mode)~="string" then return nil end
  mode=mode:lower()
  if mode=="nite" then mode="night" end
  if mode=="day" or mode=="night" or mode=="dusk" or mode=="dawn" or mode=="cycle" or mode=="sync" then return mode end
  return nil
end

local function dialToHours(dn,t)
  local cycle=tonumber(dn and dn.CYCLE)
  local dayLen=tonumber(dn and dn.DAY_LEN)
  if type(t)=="number" and t==t and cycle and cycle>24 and dayLen and dayLen>0 and dayLen<cycle then
    t=t%cycle
    if t<dayLen then return (6+(t/dayLen)*12)%24 end
    return (18+((t-dayLen)/(cycle-dayLen))*12)%24
  end
  if type(t)=="number" and t==t and (not cycle or cycle<=24) then return t%24 end
  return nil
end

-- Hours 0..24 from Dramatic Shape's dial.  Its clock is `CYCLE` seconds
-- around with the sun owning the first `DAY_LEN` of it, so the mapping is
-- "the sun's half is 06:00-18:00, the moon's half is the rest" -- which
-- puts its pinned DAY at our noon and its pinned NIGHT at our midnight.
local function voxelHours(dn)
  local mode=hostModeOf(dn)
  local ok,hour=pcall(function()
    -- Explicit host pins are presentation commands, not ordinary clock samples.
    -- Resolve their authored dial position directly so NIGHT can never be
    -- mistaken for a stale wall-clock/day sample during an options change.
    if mode and mode~="cycle" and mode~="sync" and type(dn.T)=="table" then
      local pinned=dialToHours(dn,dn.T[mode])
      if pinned~=nil then return pinned end
    end

    -- IMPORTANT: use the host's EFFECTIVE game-time dial first. Modern voxel
    -- hosts expose `hours()` as raw wall-clock time even while their selected
    -- mode is CYCLE/DAY/NIGHT/DUSK/DAWN.
    if type(dn.time)=="function" then
      local t=dn.time()
      local mapped=dialToHours(dn,t)
      if mapped~=nil then return mapped end
    end
    -- Raw host/device hours are only a compatibility fallback when no effective
    -- game-time dial can be interpreted.
    if type(dn.hours)=="function" then
      local h=dn.hours()
      if type(h)=="number" and h==h then return h%24 end
    end
    return nil
  end)
  if ok and type(hour)=="number" and hour==hour then return hour,mode end
  ds.broken=true
  return nil,mode
end

--- Call when a voxel host supplies day/night time. Weather FX follows that clock
--- through AUTO instead of disabling astronomy. The host may still own its own
--- flat screen grade; CelestialEngine drives world lighting from the shared time.
function TOD.setHostOwnsClock(yes)
  TOD._forceOffByHost = yes and true or false -- retained for older callers/tests
  TOD._hostOwnsGrade = TOD._forceOffByHost
  ds.tried = false
  ds.DayNight = nil
  ds.broken = false
  TOD.hostMode = nil
  if yes then TOD.pin = nil end
end

function TOD.update(dt)
  local cfg = Config.get().time
  -- Menu OFF is authoritative and live. Do not mutate cfg.source: toggling ON
  -- again should resume the user's configured source exactly as it was.
  if not menuDaytimeOn() then
    TOD.pin = nil
    -- OFF means Weather FX must stop owning the clock/bias/grade, but on a
    -- supported voxel host the celestial layer still needs the host's live hour
    -- so our world-space sun/moon (and their shadows) do not freeze at noon.
    -- This is PASSIVE observation only: world.tod still passes through and the
    -- Weather FX grade remains disabled below. Hosts without a readable clock
    -- retain the neutral daytime fallback used historically.
    local dn = dayNight()
    local h,hostMode
    if dn then h,hostMode=voxelHours(dn) end
    TOD.hostMode=hostMode
    if type(h) == "number" and h == h then
      TOD.hour = h % 24
      TOD.tod = TOD.phaseAt(TOD.hour)
      TOD.source = "host-passive"
      trackGameDay(TOD.hour,TOD.source,(cfg.cycleMinutes or 24)*60)
      TOD._lastEffectiveSource=TOD.source
    else
      TOD.hour, TOD.tod, TOD.source = 13, "DAY", "off"
      trackGameDay(TOD.hour,TOD.source,(cfg.cycleMinutes or 24)*60)
      TOD._lastEffectiveSource=TOD.source
    end
    return
  end
  if cfg.source == "off" then
    TOD.hostMode=nil
    TOD.hour, TOD.tod, TOD.source = 13, "DAY", "off"
    trackGameDay(TOD.hour,TOD.source,(cfg.cycleMinutes or 24)*60)
    TOD._lastEffectiveSource=TOD.source
    return
  end

  dt = tonumber(dt) or 0
  if dt < 0 or dt ~= dt then dt = 0 end
  if dt > 0.25 then dt = 0.25 end
  if dt > 0 then TOD.elapsed = TOD.elapsed + dt end

  -- A pinned rung outranks every clock source: it exists to answer "is
  -- this drawing at all", and an answer the clock could override would not
  -- be one.
  if TOD.pin then
    TOD.hostMode=nil
    TOD.hour = FIXED_HOUR[TOD.pin] or 13
    TOD.tod = TOD.pin
    TOD.source = "pinned"
    trackGameDay(TOD.hour,TOD.source,(cfg.cycleMinutes or 24)*60)
    TOD._lastEffectiveSource=TOD.source
    return
  end

  local hour = nil
  local source = cfg.source

  if source == "auto" then
    local dn = dayNight()
    if dn then
      local hostMode
      hour,hostMode = voxelHours(dn)
      TOD.hostMode=hostMode
      if hour then TOD.source = (ds.id == "DRAMALESS_SHAPE") and "dramaless" or "voxel" end
    end
    if not hour then source = "cycle" end
  end

  if source ~= "auto" then TOD.hostMode=nil end

  if not hour and source == "system" then
    local ok, t = pcall(os.date, "*t")
    if ok and type(t) == "table" then
      hour = (t.hour or 12) + (t.min or 0) / 60
      TOD.source = "system"
    else
      source = "cycle"
    end
  end

  if not hour and source == "fixed" then
    hour = FIXED_HOUR[cfg.fixedPhase] or 13
    TOD.source = "fixed"
  end

  local period = math.max(30, (cfg.cycleMinutes or 24) * 60)
  if not hour then
    local changedSource = TOD._lastEffectiveSource ~= "cycle"
    local changedPeriod = TOD._lastCyclePeriod and math.abs(TOD._lastCyclePeriod-period)>1e-6
    if TOD._cycleOffset==nil or changedSource or changedPeriod then
      -- Rebase the accelerated dial onto the hour the player is currently
      -- seeing. Switching HOST/SYSTEM -> CYCLE or changing GAME DAY LENGTH
      -- therefore continues from the same sky instead of teleporting it.
      local phase=((tonumber(TOD.hour) or 13)%24)/24*period
      TOD._cycleOffset=(phase-(tonumber(TOD.elapsed) or 0))%period
    end
    hour = ((((TOD.elapsed or 0)+(TOD._cycleOffset or 0))%period)/period)*24
    TOD.source = "cycle"
  end

  TOD.hour = hour % 24
  TOD.tod = TOD.phaseAt(TOD.hour)
  trackGameDay(TOD.hour,TOD.source,period)
  TOD._lastEffectiveSource=TOD.source
  TOD._lastCyclePeriod=period
end

-- 0 = deep night, 1 = full daylight.  The number AUTO weather weights
-- against; a cosine over the daylight window so dawn and dusk ramp rather
-- than snap.
function TOD.daylight()
  local ok, Sim = pcall(V.require, "CelestialSim")
  if ok and Sim and Sim.sample then
    local ok2, snap = pcall(Sim.sample, TOD.hour)
    if ok2 and snap and type(snap.daylight) == "number" then
      return math.max(0.03, math.min(1, snap.daylight))
    end
  end
  local h = TOD.hour
  local x = (h - 6) / 12
  if x <= 0 or x >= 1 then return 0.05 end
  return math.max(0.05, math.sin(x * math.pi) ^ 0.55)
end

function TOD.isNight()
  return TOD.tod == "NITE"
end

-- Public answer for the engine's documented world.tod hook.  Returning the
-- caller's base value when Weather FX time is disabled is important: OFF means
-- "do not own time", not "force DAY".  publishTod is a real config switch now
-- rather than an inert field.
function TOD.worldTod(base)
  local cfg = Config.get().time or {}
  if cfg.publishTod == false then return base end
  if not menuDaytimeOn() or cfg.source == "off" or TOD.source == "off" then
    return base
  end
  if type(TOD.tod) == "string" and TOD.tod ~= "" then return TOD.tod end
  return base
end

-- ------- the grade
--
-- Returns multiply rgb and additive rgb for the current hour, already
-- scaled by config strength and by how much of it reaches an interior.
-- Returns nil when there is nothing to draw, which is the common case
-- (mid-day, or the grade switched off) and costs the compositor a nil
-- check rather than an identity rectangle.

local function lerp(a, b, t) return a + (b - a) * t end

function TOD.grade(indoors)
  local cfg = Config.get().time
  if not menuDaytimeOn() then return nil end
  -- In 3D the voxel host + CelestialEngine own environmental illumination;
  -- suppress Weather FX's legacy finished-frame grade to avoid double tinting.
  if TOD._hostOwnsGrade and not indoors then return nil end
  if not cfg.grade or cfg.source == "off" then return nil end
  local strength = cfg.gradeStrength or 1
  if indoors then
    -- Menu INDOORS row: OFF = no indoor grade; TINT = config indoor strength.
    local indoorMul = tonumber(cfg.indoors) or 0
    pcall(function()
      local S = V.require("Settings")
      if S and S.get then
        if S.get("indoors") == "off" then indoorMul = 0
        elseif S.get("indoors") == "tint" and indoorMul <= 0 then indoorMul = 0.55 end
      end
    end)
    strength = strength * indoorMul
  end
  if strength <= 0.001 then return nil end

  local h = TOD.hour
  -- find the bracketing anchors on the circular list
  local prev, next_ = TOD.PHASES[1], TOD.PHASES[#TOD.PHASES]
  for i = 1, #TOD.PHASES - 1 do
    if h >= TOD.PHASES[i].at and h < TOD.PHASES[i + 1].at then
      prev, next_ = TOD.PHASES[i], TOD.PHASES[i + 1]
      break
    end
  end
  local span, into
  if h < TOD.PHASES[1].at then
    -- before the first anchor: wrap from the last (both are NITE, so the
    -- blend is a no-op and this is really just "it is the small hours")
    prev, next_ = TOD.PHASES[#TOD.PHASES], TOD.PHASES[1]
    span = (24 - prev.at) + next_.at
    into = (h + (24 - prev.at)) / span
  elseif h >= TOD.PHASES[#TOD.PHASES].at then
    prev, next_ = TOD.PHASES[#TOD.PHASES], TOD.PHASES[1]
    span = (24 - prev.at) + next_.at
    into = (h - prev.at) / span
  else
    span = next_.at - prev.at
    into = span > 0 and (h - prev.at) / span or 0
  end
  -- smoothstep, so an anchor is a plateau rather than a corner
  into = into * into * (3 - 2 * math.max(0, math.min(1, into)))

  local mr = lerp(prev.mul[1], next_.mul[1], into)
  local mg = lerp(prev.mul[2], next_.mul[2], into)
  local mb = lerp(prev.mul[3], next_.mul[3], into)
  local ar = lerp(prev.add[1], next_.add[1], into) * strength
  local ag = lerp(prev.add[2], next_.add[2], into) * strength
  local ab = lerp(prev.add[3], next_.add[3], into) * strength

  -- pull the multiply toward white by (1 - strength)
  mr = 1 - (1 - mr) * strength
  mg = 1 - (1 - mg) * strength
  mb = 1 - (1 - mb) * strength

  -- Night ambient vs distance to buildings (true night only).
  -- ≤5 steps: lightest; ≥20 steps: clearly darker night. Independent of render distance.
  if not indoors and TOD.isNight and TOD.isNight() then
    local scale = 1
    pcall(function()
      local BL = nil
      if not BL then pcall(function() BL = V.require("BuildingLight") end) end
      if BL and BL.nightAmbientScale then scale = BL.nightAmbientScale() end
    end)
    if type(scale) == "number" and scale < 0.999 then
      mr, mg, mb = mr * scale, mg * scale, mb * scale
      -- Extra cool darkness in the far wild so night reads as night
      local far = math.max(0, (1 - scale) / 0.52)  -- 0 near, ~1 at AMBIENT_FAR
      mr = mr * (1 - 0.06 * far)
      mg = mg * (1 - 0.04 * far)
      mb = math.min(1, mb * (1 + 0.08 * far))
    end
  end

  -- Nothing to draw at full daylight: DAY is exactly neutral, so the
  -- common case is free rather than an identity multiply per frame.
  if mr > 0.998 and mg > 0.998 and mb > 0.998
      and ar < 0.002 and ag < 0.002 and ab < 0.002 then
    return nil
  end
  return mr, mg, mb, ar, ag, ab
end

function TOD.describe()
  local mode=TOD.hostMode and (":"..tostring(TOD.hostMode)) or ""
  return ("%s %02d:%02d/%s%s"):format(TOD.tod, math.floor(TOD.hour),
    math.floor((TOD.hour % 1) * 60), TOD.source,mode)
end

return TOD
