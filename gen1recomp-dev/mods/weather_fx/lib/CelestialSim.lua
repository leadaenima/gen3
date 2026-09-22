-- CelestialSim — physically-inspired celestial simulation for Weather FX.
--
-- Camera is the observer. It NEVER participates in celestial orientation.
-- The simulation owns one coherent world-space answer for:
--   * seasonal sunrise / sunset / day length
--   * default voxel-friendly East -> overhead -> West vertical body orbit
--   * civil / nautical / astronomical twilight
--   * lunar orbit, synodic phase, illumination and moonlight
--   * sidereal star-vault rotation about the north celestial pole
--   * rare solar/lunar eclipse alignment
--
-- World basis:
--   +X EAST, +Y UP, +Z SOUTH. North is therefore -Z.
-- Kanto/Johto sit close enough to 35°N that 35° is a useful physical default
-- for seasonal timing and the sidereal star vault. Sun/moon presentation uses
-- the fixed East-Up-West world plane by default because that is the intended
-- voxel-game read; Config.celestial.verticalOrbit=false restores the fully
-- latitude/declination horizon path.

local V = ...
local Sim = {}

Sim.LAYER = { stars = 1.00, sun = 0.96, moon = 0.94 }
Sim.SYNODIC_MONTH = 29.530588
Sim.DRACONIC_MONTH = 27.212221
Sim.ANOMALISTIC_MONTH = 27.554550
Sim.TROPICAL_YEAR = 365.2422
Sim.AXIAL_TILT = 23.43928
Sim.DEFAULT_LATITUDE = 35.0

local PI, TWO_PI = math.pi, math.pi * 2
local RAD = PI / 180
local DEG = 180 / PI
local sin, cos, sqrt, asin, acos, abs = math.sin, math.cos, math.sqrt, math.asin, math.acos, math.abs

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b end
  return x
end
local function clamp01(x) return clamp(x, 0, 1) end
local function smooth(a, b, x)
  if a == b then return x >= b and 1 or 0 end
  local t = clamp01((x - a) / (b - a))
  return t * t * (3 - 2 * t)
end
local function norm2pi(a)
  a = a % TWO_PI
  if a < 0 then a = a + TWO_PI end
  return a
end
local function lerp(a,b,t) return a + (b-a)*t end
local function mix3(a,b,t)
  return { lerp(a[1],b[1],t), lerp(a[2],b[2],t), lerp(a[3],b[3],t) }
end

local function root(name)
  local ok, m = pcall(V.require, name)
  if ok then return m end
  return nil
end

local function celestialConfig()
  local cfg = root("Config")
  cfg = cfg and cfg.get and cfg.get() or nil
  return (cfg and cfg.celestial) or {}
end

function Sim.latitude()
  local c = celestialConfig()
  local n = tonumber(c.latitude) or Sim.DEFAULT_LATITUDE
  return clamp(n, -66, 66)
end

function Sim.hour(override)
  if type(override) == "number" and override == override then return override % 24 end
  local TOD = root("TimeOfDay")
  local h = TOD and TOD.hour
  if type(h) == "number" and h == h then return h % 24 end
  return 12
end

local function leapBefore(year)
  -- Leap days from 2000-01-01 up to the beginning of `year`.
  local n = 0
  if year >= 2000 then
    for y = 2000, year - 1 do
      if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then n = n + 1 end
    end
  else
    for y = year, 1999 do
      if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then n = n - 1 end
    end
  end
  return n
end

local function systemCalendar()
  local ok, t = pcall(os.date, "*t")
  if not ok or type(t) ~= "table" then return nil end
  local yday = tonumber(t.yday)
  if not yday then return nil end
  return t, yday - 1
end

-- 0..365 seasonal position. System clock follows the real calendar; accelerated
-- clocks map the configured in-game year across a tropical year so seasons,
-- daylight length and weather weighting move together.
function Sim.dayIndex(override)
  if type(override) == "number" and override == override then
    return override % Sim.TROPICAL_YEAR
  end
  local TOD = root("TimeOfDay")
  if TOD and TOD.source == "system" then
    local _, d = systemCalendar()
    if d then return d end
  end
  local cfg = root("Config")
  cfg = cfg and cfg.get and cfg.get() or {}
  local tcfg = cfg.time or {}
  local scfg = cfg.seasons or {}
  local dayPeriod = math.max(30, (tonumber(tcfg.cycleMinutes) or 24) * 60)
  local daysPerSeason = math.max(1, math.floor(tonumber(scfg.daysPerSeason) or 15))
  local yearDays = daysPerSeason * 4
  local elapsed = TOD and tonumber(TOD.elapsed) or 0
  local gameDay = (elapsed / dayPeriod) % yearDays
  return (gameDay / yearDays) * Sim.TROPICAL_YEAR
end

-- Continuous day serial used by lunar phase. With SYSTEM time this is anchored
-- to the well-known 2000-01-06 new moon; accelerated clocks use their own day
-- counter so lunar phases remain stable and deterministic within the save.
function Sim.daySerial(hour, dayOverride)
  hour = Sim.hour(hour)
  if type(dayOverride) == "number" and dayOverride == dayOverride then
    return dayOverride + hour / 24
  end
  local TOD = root("TimeOfDay")
  if TOD and TOD.source == "system" then
    local t, d = systemCalendar()
    if t and d then
      local years = (tonumber(t.year) or 2000) - 2000
      local serial = years * 365 + leapBefore(tonumber(t.year) or 2000) + d
      -- New moon epoch: 2000-01-06 ~18:14 local-neutral approximation.
      return serial + hour / 24 - 5.7597
    end
  end
  -- Do not start every accelerated save at the same new-moon/node alignment;
  -- a deterministic epoch offset gives a natural initial phase while explicit
  -- dayOverride remains a precise astronomy-test/debug coordinate above.
  return Sim.dayIndex(dayOverride) + hour / 24 + 8.25
end


-- Lunar time is deliberately separate from the season-scaled dayIndex().
-- Accelerated worlds can compress a whole year into only 60 game days; using
-- that seasonal coordinate made the moon jump ~6 lunar days every night.
-- Live lunar presentation is locked noon-to-noon so one evening and the
-- following pre-dawn hours always show the same phase. Explicit dayOverride
-- remains continuous for astronomy tests/debug positioning.
function Sim.lunarDaySerial(hour, dayOverride)
  hour=Sim.hour(hour)
  if type(dayOverride)=="number" and dayOverride==dayOverride then
    return dayOverride+hour/24
  end
  local TOD=root("TimeOfDay")
  if TOD and TOD.source=="system" then
    local t,d=systemCalendar()
    if t and d then
      local year=tonumber(t.year) or 2000
      local years=year-2000
      local calendarDay=years*365+leapBefore(year)+d
      -- Assign the evening to the following civil date, so evening through the
      -- next morning is one stable observational night. Keep the historical
      -- 2000-01-06 ~18:14 new-moon epoch offset.
      local nightDay=calendarDay+(hour>=12 and 1 or 0)
      return nightDay-5.7597
    end
  end
  local cfg=root("Config"); cfg=cfg and cfg.get and cfg.get() or {}
  local tcfg=cfg.time or {}
  local period=math.max(30,(tonumber(tcfg.cycleMinutes) or 24)*60)
  local gameDays
  if TOD and type(TOD.gameDaySerial)=="function" then
    local ok,v=pcall(TOD.gameDaySerial); if ok then gameDays=tonumber(v) end
  end
  if gameDays==nil then gameDays=(TOD and tonumber(TOD.elapsed) or 0)/period end
  local nightIndex=math.floor(gameDays+0.5) -- rollover at noon, never mid-night
  return nightIndex+8.25
end

function Sim.moonPhaseLit(phase, illumination, x, y)
  phase=(tonumber(phase) or 0)%1
  illumination=clamp01(tonumber(illumination) or 0)
  x=tonumber(x) or 0; y=tonumber(y) or 0
  if x*x+y*y>1 then return false end
  local limb=sqrt(math.max(0,1-y*y))
  local terminator=(1-2*illumination)*limb
  -- Northern-hemisphere presentation: waxing light grows from the right,
  -- waning light shrinks toward the left. At exactly 50% this is a true half.
  if phase<0.5 then return x>=terminator end
  return x<=-terminator
end

function Sim.solarDeclination(day)
  day = Sim.dayIndex(day)
  local tilt = tonumber(celestialConfig().axialTilt) or Sim.AXIAL_TILT
  -- Good compact solar declination approximation; equinox near day 80.
  return tilt * sin(TWO_PI * (day - 80.0) / Sim.TROPICAL_YEAR)
end

local function horizonVector(hourAngle, declDeg, latDeg)
  local H, d, p = hourAngle, declDeg * RAD, latDeg * RAD
  local east = -cos(d) * sin(H)
  local north = cos(p) * sin(d) - sin(p) * cos(d) * cos(H)
  local up = sin(p) * sin(d) + cos(p) * cos(d) * cos(H)
  local south = -north
  local L = sqrt(east*east + up*up + south*south)
  if L > 1e-9 then east,up,south = east/L,up/L,south/L end
  return east, up, south
end

local function altAz(dx,dy,dz)
  local alt = asin(clamp(dy,-1,1))
  -- 0=north, 90=east, 180=south, 270=west.
  local az = math.atan2(dx, -dz)
  if az < 0 then az = az + TWO_PI end
  return alt, az
end

-- House-rule voxel orbit. The player asked for a visually physical daily arc:
-- one fixed side of the map -> overhead -> the opposite side. Keeping the
-- orbit in world X/Y means camera yaw and player movement can never turn it
-- into a flat circle around the player. Seasonal sunrise/sunset still control
-- how quickly the body traverses the visible half of the orbit.
local function verticalOrbitAngle(hour, sunrise, sunset)
  hour = hour % 24
  local dayLen = math.max(0.01, sunset - sunrise)
  if hour >= sunrise and hour <= sunset then
    return math.pi * ((hour - sunrise) / dayLen)
  end
  local h = hour
  if h < sunrise then h = h + 24 end
  local nightLen = math.max(0.01, (24 - sunset) + sunrise)
  return math.pi + math.pi * ((h - sunset) / nightLen)
end

local function verticalOrbitVector(angle)
  local dx,dy,dz = cos(angle),sin(angle),0
  local L=sqrt(dx*dx+dy*dy)
  if L>1e-9 then dx,dy=dx/L,dy/L end
  return dx,dy,dz
end

function Sim.sunriseSunset(day)
  local lat = Sim.latitude() * RAD
  local dec = Sim.solarDeclination(day) * RAD
  local x = -math.tan(lat) * math.tan(dec)
  if x <= -1 then return 0, 24, 24 end
  if x >= 1 then return 12, 12, 0 end
  local H = acos(clamp(x,-1,1))
  local half = H * DEG / 15
  return 12-half, 12+half, half*2
end

local function twilightState(altDeg)
  local stage
  if altDeg >= 6 then stage = "DAY"
  elseif altDeg >= 0 then stage = "GOLDEN"
  elseif altDeg >= -6 then stage = "CIVIL"
  elseif altDeg >= -12 then stage = "NAUTICAL"
  elseif altDeg >= -18 then stage = "ASTRONOMICAL"
  else stage = "NIGHT" end
  local daylight = smooth(-6, 8, altDeg)
  -- Deep-sky visibility follows solar altitude continuously. Full daylight is
  -- zero; after the sun drops below the horizon the stars/planets ease in
  -- through twilight and reach full brightness at astronomical night. The
  -- same curve runs in reverse before sunrise, so there is never a dawn/dusk
  -- pop.
  local starVis = smooth(0, 1, (-altDeg - 2) / 16) -- 0 at -2°, 1 at -18°
  return stage, daylight, starVis
end


local function moonriseStarVisibility(hour, sunrise, sunset)
  hour=(tonumber(hour) or 0)%24
  local nightLen=math.max(0.01,(24-sunset)+sunrise)
  local progress
  if hour>=sunset then progress=(hour-sunset)/nightLen
  elseif hour<sunrise then progress=((24-sunset)+hour)/nightLen
  else return 0 end
  progress=clamp01(progress)
  -- First stars appear the instant the paired moon starts rising. They reach
  -- full authored brightness exactly one quarter of the way through the night,
  -- stay fully readable through the deep-night window, then ease out before
  -- sunrise rather than popping off at dawn.
  local rise=smooth(0.0,0.25,progress)
  -- Quarter-night is the single brightness peak. After that, keep a strong
  -- readable sky but let it slowly soften before the final dawn fade.
  local afterPeak=1.0-0.28*smooth(0.25,0.82,progress)
  local dawn=1.0-smooth(0.82,1.0,progress)
  return clamp01(math.min(rise,afterPeak,dawn))
end

local function sunColor(altDeg)
  -- Wide, continuous optical-depth ramp. The old -4..+4 transition compressed
  -- most of the visible colour change into a few minutes and read as a sudden
  -- orange switch. These broader bands let white -> gold -> amber -> deep warm
  -- red evolve naturally across the whole approach to and passage through the
  -- horizon.
  local deep = {0.70,0.13,0.035}
  local warm = {1.00,0.38,0.085}
  local amber = {1.00,0.63,0.22}
  local gold = {1.00,0.84,0.54}
  local white = {1.00,0.985,0.94}
  if altDeg <= -8 then return deep end
  if altDeg < 0 then return mix3(deep,warm,smooth(-8,0,altDeg)) end
  if altDeg < 8 then return mix3(warm,amber,smooth(0,8,altDeg)) end
  if altDeg < 18 then return mix3(amber,gold,smooth(8,18,altDeg)) end
  return mix3(gold,white,smooth(18,38,altDeg))
end

local function skyPalette(altDeg, moonLight)
  local nightTop={0.006,0.010,0.030}; local nightHaze={0.025,0.035,0.080}
  local astroTop={0.035,0.045,0.105}; local astroHaze={0.13,0.08,0.16}
  local civilTop={0.18,0.24,0.48}; local civilHaze={0.92,0.34,0.20}
  local dayTop={0.16,0.42,0.78}; local dayHaze={0.62,0.82,1.00}
  local top,haze
  if altDeg < -18 then
    top,haze=nightTop,nightHaze
  elseif altDeg < -8 then
    local t=smooth(-18,-8,altDeg); top=mix3(nightTop,astroTop,t); haze=mix3(nightHaze,astroHaze,t)
  elseif altDeg < 8 then
    local t=smooth(-8,8,altDeg); top=mix3(astroTop,civilTop,t); haze=mix3(astroHaze,civilHaze,t)
  else
    local t=smooth(8,24,altDeg); top=mix3(civilTop,dayTop,t); haze=mix3(civilHaze,dayHaze,t)
  end
  if altDeg < -6 and moonLight > 0 then
    local m=clamp01(moonLight*2.3)
    top=mix3(top,{0.055,0.080,0.16},m*0.45)
    haze=mix3(haze,{0.09,0.12,0.21},m*0.40)
  end
  -- 8.1.26 directional-atmosphere palette authority. The horizon should carry
  -- the long optical-path orange/red while the zenith remains substantially
  -- cooler. The previous palette reached the right colours but only weakly at
  -- the actual horizon, reading as a slight global tint instead of a sunrise.
  local warmIn=smooth(-12,-1.0,altDeg)
  local warmOut=1-smooth(7,24,altDeg)
  local golden=clamp01(warmIn*warmOut)
  if golden>0 then
    top=mix3(top,{0.10,0.16,0.36},golden*0.18)
    haze=mix3(haze,{1.00,0.25,0.055},golden*0.72)
  end
  local mid=mix3(top,haze,0.48)
  if golden>0 then mid=mix3(mid,{0.66,0.27,0.22},golden*0.26) end
  return top,mid,haze
end

function Sim.lunarPhase(hour, dayOverride)
  local serial = Sim.lunarDaySerial(hour, dayOverride)
  local age = serial % Sim.SYNODIC_MONTH
  if age < 0 then age = age + Sim.SYNODIC_MONTH end
  local phase = age / Sim.SYNODIC_MONTH
  local angle = phase * TWO_PI
  local illum = (1 - cos(angle)) * 0.5
  local name
  if phase < 0.03125 or phase >= 0.96875 then name="NEW"
  elseif phase < 0.21875 then name="WAXING_CRESCENT"
  elseif phase < 0.28125 then name="FIRST_QUARTER"
  elseif phase < 0.46875 then name="WAXING_GIBBOUS"
  elseif phase < 0.53125 then name="FULL"
  elseif phase < 0.71875 then name="WANING_GIBBOUS"
  elseif phase < 0.78125 then name="LAST_QUARTER"
  else name="WANING_CRESCENT" end
  return phase, angle, illum, age, name
end

local function angularSep(a,b)
  local d = clamp(a.dx*b.dx + a.dy*b.dy + a.dz*b.dz, -1, 1)
  return acos(d)
end

-- Rotate one fixed celestial direction around the real north celestial pole.
-- This is what makes stars rise/set instead of merely sliding around world UP.
function Sim.starRotator(angle)
  local p=Sim.latitude()*RAD
  local ax,ay,az=0,sin(p),-cos(p)
  local c,sn=cos(angle),sin(angle)
  return function(dx,dy,dz)
    local dot=dx*ax+dy*ay+dz*az
    local cx=ay*dz-az*dy
    local cy=az*dx-ax*dz
    local cz=ax*dy-ay*dx
    return dx*c+cx*sn+ax*dot*(1-c),
           dy*c+cy*sn+ay*dot*(1-c),
           dz*c+cz*sn+az*dot*(1-c)
  end
end

function Sim.rotateStar(dx,dy,dz,angle)
  return Sim.starRotator(angle)(dx,dy,dz)
end

-- User-facing celestial vault speed. Keep the physical sidereal solution intact
-- for astronomy/debug consumers, then deliberately slow the rendered deep-sky
-- vault to 50% of its previous rate. Stars, planets, the Milky Way and
-- constellation geometry all consume the same angle so they never drift apart.
Sim.STAR_VAULT_RATE = 0.25

function Sim.siderealAngle(hour, dayOverride)
  hour = Sim.hour(hour)
  local d = Sim.daySerial(hour, dayOverride)
  -- Physical reference: 1.0027379 stellar rotations per solar day.
  return norm2pi(TWO_PI * d * 1.00273790935)
end

function Sim.starVaultAngle(hour, dayOverride)
  -- Apply the display rate to the unwrapped sidereal day serial, then wrap
  -- exactly once. Scaling an already-wrapped angle causes a discontinuity at
  -- 2pi (the old 0.5x path could snap by ~pi); this form is continuous for any
  -- STAR_VAULT_RATE, including the current 0.25x slow-sky setting.
  hour = Sim.hour(hour)
  local d = Sim.daySerial(hour, dayOverride)
  return norm2pi(TWO_PI * d * 1.00273790935 * Sim.STAR_VAULT_RATE)
end

-- Fraction of an apparent circular disc that is above the geometric horizon.
-- This is the exact circle-segment area fraction, not a center-point switch.
-- It prevents a large rendered sun/moon from vanishing while half of the disc
-- is still visible: upper limb first appears at -radius, the disc is 50%
-- visible when its center reaches the horizon, and the lower limb clears at
-- +radius.
function Sim.discHorizonFraction(altDeg, radiusDeg)
  altDeg=tonumber(altDeg) or -90
  radiusDeg=math.max(0.05,tonumber(radiusDeg) or 1)
  local x=altDeg/radiusDeg
  if x<=-1 then return 0 end
  if x>=1 then return 1 end
  x=clamp(x,-1,1)
  return clamp01(0.5 + (asin(x) + x*sqrt(math.max(0,1-x*x))) / PI)
end

-- Local solar halo belongs to *horizon contact*, not to the whole low-sun
-- period. A fully visible disc has no sunset halo; as soon as the lower limb
-- crosses the horizon the halo grows smoothly, peaks around half-set, then
-- eases back to zero with zero slope as the last upper limb disappears.
-- Using the already limb-aware disc fraction guarantees there is no altitude
-- threshold that can pop the halo on/off. The same envelope naturally mirrors
-- at sunrise.
function Sim.sunHorizonHalo(altDeg, radiusDeg)
  local f=Sim.discHorizonFraction(altDeg,radiusDeg or 4.5)
  if f<=0 or f>=1 then return 0 end
  local q=sin(PI*f)
  return clamp01(q*q)
end

-- Compatibility for stars/legacy callers that need a point-like horizon fade.
function Sim.horizonFade(dy)
  if type(dy) ~= "number" then return 0 end
  return smooth(-0.035, 0.13, dy)
end

-- Compatibility: old callers called this "solarAlpha" and used it as a vault
-- rotation angle. It now returns the real sidereal angle; sun direction itself
-- comes from sample().
function Sim.solarAlpha(hour) return Sim.siderealAngle(hour) end

function Sim.sample(hour, dayOverride)
  hour = Sim.hour(hour)
  local day = Sim.dayIndex(dayOverride)
  local lat = Sim.latitude()
  local decl = Sim.solarDeclination(day)
  local sunrise,sunset,dayLen=Sim.sunriseSunset(day)
  local H = (hour - 12) * 15 * RAD
  local cc=celestialConfig()
  local vertical = cc.verticalOrbit ~= false
  local sunOrbitAngle
  local sdx,sdy,sdz
  if vertical then
    sunOrbitAngle=verticalOrbitAngle(hour,sunrise,sunset)
    sdx,sdy,sdz=verticalOrbitVector(sunOrbitAngle)
  else
    sdx,sdy,sdz = horizonVector(H,decl,lat)
  end
  local sAlt,sAz = altAz(sdx,sdy,sdz)
  local sAltDeg=sAlt*DEG
  local stage,daylight,starVis=twilightState(sAltDeg)

  local phase,phaseAngle,illum,age,phaseName=Sim.lunarPhase(hour,dayOverride)
  -- New moon shares the sun path; full moon is opposite it. In the default
  -- voxel presentation both bodies use the same fixed East-Up-West world
  -- plane, so the moon also rises, crosses overhead, and sets rather than
  -- orbiting horizontally around the player. The optional astronomy path
  -- retains latitude/declination behavior.
  local lunarSerial=Sim.lunarDaySerial(hour,dayOverride)
  local node = TWO_PI*lunarSerial/Sim.DRACONIC_MONTH
  local mdx,mdy,mdz
  if vertical then
    -- House rule / requested presentation: lunar *phase* controls the lit
    -- hemisphere, not the daily rise/set position. Keep the visible moon on
    -- the same continuous great-circle exactly opposite the sun so there is
    -- never a phase-dependent teleport to zenith at sunset. Set
    -- celestial.pairedMoonOrbit=false to restore phase-shifted moonrise times.
    local moonAngle
    if cc.pairedMoonOrbit == false then moonAngle=(sunOrbitAngle or 0)-phaseAngle
    else moonAngle=(sunOrbitAngle or 0)+PI end
    mdx,mdy,mdz=verticalOrbitVector(moonAngle)
  else
    local Hm = H - phaseAngle
    local ecliptic = TWO_PI*(day-80)/Sim.TROPICAL_YEAR + phaseAngle
    local mDecl = Sim.AXIAL_TILT*sin(ecliptic) + 5.14*sin(node)
    mDecl = clamp(mDecl,-28.6,28.6)
    mdx,mdy,mdz=horizonVector(Hm,mDecl,lat)
  end
  local mAlt,mAz=altAz(mdx,mdy,mdz)
  local mAltDeg=mAlt*DEG
  if vertical and cc.pairedMoonOrbit ~= false then
    starVis=moonriseStarVisibility(hour,sunrise,sunset)
  end

  local sunAbove=sAltDeg>-0.833
  local moonAbove=mAltDeg>-0.3
  local sunIntensity=smooth(-4,12,sAltDeg)
  local moonAltitude=smooth(-2,15,mAltDeg)
  local moonIntensity=(illum^0.72)*moonAltitude*0.22

  -- Eclipses require syzygy AND proximity to a lunar node. Severity is smooth
  -- so the same simulation drives partial and near-total events.
  local nodeProximity = 1 - smooth(0.08,0.30,abs(sin(node)))
  local newProx = 1 - smooth(0.015,0.065,math.min(phase,1-phase))
  local fullProx = 1 - smooth(0.015,0.065,abs(phase-0.5))
  local solarE = clamp01(newProx * nodeProximity)
  local lunarE = clamp01(fullProx * nodeProximity)
  -- During a real solar eclipse the apparent moon converges on the sun. Blend
  -- the simplified lunar orbit toward that alignment only while the event is
  -- active; this makes the rare simulation visibly self-consistent.
  if solarE > 0.02 and sunAbove then
    local k=solarE*0.97
    mdx=mdx*(1-k)+sdx*k; mdy=mdy*(1-k)+sdy*k; mdz=mdz*(1-k)+sdz*k
    local L=sqrt(mdx*mdx+mdy*mdy+mdz*mdz); if L>1e-8 then mdx,mdy,mdz=mdx/L,mdy/L,mdz/L end
    mAlt,mAz=altAz(mdx,mdy,mdz); mAltDeg=mAlt*DEG; moonAbove=mAltDeg>-0.3
  end

  local sep=angularSep({dx=sdx,dy=sdy,dz=sdz},{dx=mdx,dy=mdy,dz=mdz})
  local sunCol=sunColor(sAltDeg)
  local top,mid,haze=skyPalette(sAltDeg,moonIntensity)

  local solarObscuration=solarE*clamp01(1-sep/(1.25*RAD))
  if solarE>0.70 and sep < 2.5*RAD then solarObscuration=math.max(solarObscuration,solarE*0.82) end
  local lunarDark=lunarE*moonAltitude

  -- Special lunar/celestial events. They are deterministic from the same
  -- accelerated/system sky clock, so save/load or camera movement cannot make
  -- an event pop in/out. Eclipses remain the physical syzygy/node solution
  -- above; the presentation events below only tint/scale the visible moon.
  local serial=lunarSerial
  local lunation=math.floor(serial/Sim.SYNODIC_MONTH)
  local anom=(serial%Sim.ANOMALISTIC_MONTH)/Sim.ANOMALISTIC_MONTH
  if anom<0 then anom=anom+1 end
  local perigee=0.5+0.5*cos(TWO_PI*anom)
  local eventsEnabled=cc.events ~= false
  local superMoon=eventsEnabled and (fullProx>0.72 and perigee>0.78)
  local seasonDay=Sim.dayIndex(dayOverride)
  local autumnDelta=abs(((seasonDay-266+Sim.TROPICAL_YEAR*.5)%Sim.TROPICAL_YEAR)-Sim.TROPICAL_YEAR*.5)
  local harvestMoon=eventsEnabled and (fullProx>0.78 and autumnDelta<18)
  -- A rare game-sky blue-moon cycle (roughly once per 33 lunations). System
  -- time still follows the real lunar phase; this presentation marker is kept
  -- deterministic and intentionally rare without depending on locale calendars.
  local blueMoon=eventsEnabled and (fullProx>0.86 and (lunation%33)==0)
  local bloodMoon=eventsEnabled and (lunarDark>0.18)
  local moonEvent='NONE'
  if bloodMoon then moonEvent='BLOOD_MOON'
  elseif blueMoon then moonEvent='BLUE_MOON'
  elseif harvestMoon then moonEvent='HARVEST_MOON'
  elseif superMoon then moonEvent='SUPERMOON' end

  local moonScale=1.0
  local moonLum=1.0
  local moonColor={0.73,0.80,1.0}
  if superMoon then moonScale=1.0+0.18*smooth(0.78,1.0,perigee); moonLum=1.16 end
  if harvestMoon then moonColor={1.00,0.72,0.32}; moonLum=math.max(moonLum,1.10) end
  if blueMoon then moonColor={0.58,0.78,1.00}; moonLum=math.max(moonLum,1.12) end
  if bloodMoon then moonColor=mix3(moonColor,{0.80,0.20,0.08},clamp01(lunarDark)); moonLum=.92 end

  local directSun=sunIntensity*(1-solarObscuration*0.96)
  local directMoon=moonIntensity*(1-lunarDark*0.72)*moonLum
  -- The in-game discs are deliberately larger than real angular sizes so
  -- they read clearly in voxel view. Visibility therefore uses their rendered
  -- apparent radii rather than point-center altitude, producing a gradual
  -- limb-by-limb rise/set instead of a hard cutoff around the horizon.
  -- 8.1.15: the 3D bodies are 40% smaller and keep a constant angular size.
  -- Keep the horizon/contact model matched to the actual rendered limb so the
  -- first/last pixel appears at the same instant the optical effects begin.
  local sunDisc=Sim.discHorizonFraction(sAltDeg,3.24)
  local moonDisc=Sim.discHorizonFraction(mAltDeg,2.16)
  local sunHalo=Sim.sunHorizonHalo(sAltDeg,3.24)
  local sunAlpha=sunDisc*clamp01(0.30+sunIntensity*0.85)
  local moonPhaseVisible=smooth(0.005,0.08,illum)
  local moonAlpha=moonDisc*clamp01(0.02+moonPhaseVisible*0.98)

  return {
    hour=hour, dayIndex=day, latitude=lat,
    sunrise=sunrise, sunset=sunset, dayLength=dayLen,
    solarDeclination=decl, siderealAngle=Sim.siderealAngle(hour,dayOverride),
    orbitMode=vertical and "VERTICAL_EAST_UP_WEST" or "LATITUDE_HORIZON",
    twilight=stage, daylight=daylight, starVisibility=starVis,
    sky={top=top,mid=mid,haze=haze},
    sun={dx=sdx,dy=sdy,dz=sdz,altitude=sAlt,altitudeDeg=sAltDeg,azimuth=sAz,azimuthDeg=sAz*DEG,
         alpha=sunAlpha,horizonFraction=sunDisc,haloStrength=sunHalo,above=sunAbove,kind="sun",intensity=directSun,color=sunCol,
         theta=sAz,el=sAlt},
    moon={dx=mdx,dy=mdy,dz=mdz,altitude=mAlt,altitudeDeg=mAltDeg,azimuth=mAz,azimuthDeg=mAz*DEG,
          alpha=moonAlpha,horizonFraction=moonDisc,above=moonAbove,kind="moon",intensity=directMoon,
          phase=phase,phaseAngle=phaseAngle,illumination=illum,ageDays=age,phaseName=phaseName,
          lunarNightSerial=lunarSerial,waxing=phase>0 and phase<0.5,
          color=moonColor,apparentScale=moonScale,luminanceScale=moonLum,event=moonEvent,
          theta=mAz,el=mAlt},
    eclipse={solar=solarE,lunar=lunarE,solarObscuration=solarObscuration,lunarDarkening=lunarDark,separation=sep},
    events={primary=moonEvent,supermoon=superMoon,harvestMoon=harvestMoon,blueMoon=blueMoon,bloodMoon=bloodMoon,
            solarEclipse=solarObscuration>0.05,lunarEclipse=lunarDark>0.05,perigee=perigee,lunation=lunation},
  }
end

function Sim.sunDir(hour) local s=Sim.sample(hour).sun; return s.dx,s.dy,s.dz end
function Sim.moonDir(hour) local m=Sim.sample(hour).moon; return m.dx,m.dy,m.dz end
function Sim.bodies(hour) return Sim.sample(hour) end

function Sim.debug(hour)
  local s=Sim.sample(hour)
  return string.format("[CelestialSim] %.2fh %s rise=%.2f set=%.2f sunAlt=%.1f moon=%s %.0f%% alt=%.1f eclipse=%.2f/%.2f",
    s.hour,s.twilight,s.sunrise,s.sunset,s.sun.altitudeDeg,s.moon.phaseName,s.moon.illumination*100,s.moon.altitudeDeg,
    s.eclipse.solar,s.eclipse.lunar)
end

function Sim.moonPhase(hour,dayOverride)
  local s=Sim.sample(hour,dayOverride)
  return s and s.moon and tonumber(s.moon.phase) or 0
end

return Sim
