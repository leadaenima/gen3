-- SEASONS.
--
-- Gen 1/2 have none, so this mod used to answer "where does it snow" with
-- altitude and water alone.  Players still ask for a calendar, and a
-- calendar is what this file is: four seasons, a hemisphere switch that
-- reverses them, seasonal multipliers on AUTO weather weights, and a
-- short on-screen banner when the season flips.
--
-- =====================================================================
-- TWO CLOCKS, ONE ANSWER
-- =====================================================================
--
--   system   real device calendar (the same source GSC used for the clock)
--   cycle    in-game year derived from TOD.elapsed / cycleMinutes
--   auto     follows whichever clock TimeOfDay is actually on
--   fixed    still advances the in-game year so the season is not frozen
--   off      seasons stay off; weight multipliers are all 1
--
-- Hemisphere only flips the mapping from month/day-of-year to season name.
-- Northern meteorological months are the default; Southern swaps them.
--
-- =====================================================================
-- NOTIFICATIONS
-- =====================================================================
--
-- Two banners share one draw path:
--
--   1. Season change  -- queued when the computed season differs from the
--      one last written to mod.save ("WINTER has begun!").
--   2. Place + season -- queued when the player enters the overworld or
--      walks into a new map, drawn under the route/town name style:
--      "Pallet Town" on the first line, "Summer" underneath.
--
-- Both are drawn for a few seconds on the HUD pass and do not touch the
-- weather channels or the state machine.  Suppressing the banner still
-- advances the season and applies the weights.

local V = ...
local mod = V.mod
local Config = V.require("Config")
local Settings = V.require("Settings")
local TOD = V.require("TimeOfDay")
local Types = V.require("Types")

local Seasons = {}

Seasons.IDS = { "SPRING", "SUMMER", "AUTUMN", "WINTER" }
Seasons.LABELS = {
  SPRING = "SPRING",
  SUMMER = "SUMMER",
  AUTUMN = "AUTUMN",
  WINTER = "WINTER",
}
-- Title-case labels for the place banner (under the location name).
Seasons.TITLE = {
  SPRING = "Spring",
  SUMMER = "Summer",
  AUTUMN = "Autumn",
  WINTER = "Winter",
}

-- Northern meteorological months -> season index (1=SPRING .. 4=WINTER)
local NORTH_BY_MONTH = {
  [12] = 4, [1] = 4, [2] = 4,
  [3]  = 1, [4] = 1, [5] = 1,
  [6]  = 2, [7] = 2, [8] = 2,
  [9]  = 3, [10] = 3, [11] = 3,
}

-- Southern: northern summer becomes southern winter, etc.
local SOUTH_OF = { [1] = 3, [2] = 4, [3] = 1, [4] = 2 }

Seasons.id = "SPRING"
Seasons.source = "none"
Seasons.notifyT = 0
Seasons.notifyText = nil
Seasons.notifyPlace = nil   -- location line for the place+season banner
Seasons._lastPersisted = nil
Seasons._bootstrapped = false
Seasons._lastMapId = nil
Seasons._seenOverworld = false

-- Capability multipliers per season.  Keys match the tags biasFor already
-- understands (wet / frozen / sunny / sandy) plus fog.  A missing key is 1.
--
-- ZERO is a hard gate: weightOf multiplies by this after geography, so
-- frozen = 0 in summer means snow/hail/blizzard cannot roll anywhere --
-- not even on Indigo Plateau.  Hemisphere only changes which months map
-- to which season; the gates below always apply to the *current* season.
--
--   SUMMER  no frozen weather (snow, blizzard, hail, sleet, thundersnow)
--   WINTER  no sunny weather (sun, heatwave, harsh sun)
--   SPRING  light snow rare; rain favoured
--   AUTUMN  light snow possible; fog and rain favoured
local MULT = {
  SPRING = { wet = 1.50, sunny = 1.20, frozen = 0.25, sandy = 0.80, fog = 1.15 },
  SUMMER = { wet = 0.75, sunny = 1.80, frozen = 0.00, sandy = 1.40, fog = 0.55 },
  AUTUMN = { wet = 1.45, sunny = 0.70, frozen = 0.55, sandy = 0.90, fog = 1.55 },
  WINTER = { wet = 0.85, sunny = 0.00, frozen = 2.80, sandy = 0.50, fog = 1.30 },
}

-- Identity-specific climatology. Broad capability tags above remain useful for
-- modded weather definitions; this matrix gives the built-in catalogue the
-- seasonal character players expect instead of treating every wet/frozen type
-- alike. ZERO is an intentional hard seasonal impossibility.
local WEATHER_MULT = {
  SPRING={RAIN_LIGHT=1.55,VERDANT_RAIN=1.85,RAIN_HEAVY=1.25,HEAVY_RAIN=1.10,STORM=1.12,MIST=1.45,FOG=1.30,SNOW_LIGHT=.18,BLIZZARD=.03,THUNDERSNOW=.05,HEATWAVE=.20,HARSH_SUN=.42},
  SUMMER={SUNNY=1.40,HARSH_SUN=1.55,HEATWAVE=1.75,STORM=1.35,RAIN_HEAVY=1.10,HEAVY_RAIN=1.22,GALE=1.08,FOG=.50,MIST=.62,SNOW_LIGHT=0,BLIZZARD=0,HAIL=.12,SLEET=0,THUNDERSNOW=0},
  AUTUMN={RAIN_LIGHT=1.35,RAIN_HEAVY=1.30,HEAVY_RAIN=1.18,FOG=1.55,MIST=1.45,STRONG_WINDS=1.40,GALE=1.45,SNOW_LIGHT=.48,SLEET=.72,HEATWAVE=.08,HARSH_SUN=.22},
  WINTER={SNOW_LIGHT=1.85,BLIZZARD=2.05,HAIL=1.45,SLEET=1.75,THUNDERSNOW=1.65,STRONG_WINDS=1.20,FOG=1.12,RAIN_LIGHT=.40,RAIN_HEAVY=.28,HEAVY_RAIN=.18,STORM=.28,SUNNY=0,HARSH_SUN=0,HEATWAVE=0,SANDSTORM=.10,DUSTSTORM=.10,VERDANT_RAIN=.22},
}

local function hemisphere()
  local v = Settings.get("hemisphere")
  if v == "southern" then return "southern" end
  return "northern"
end

local function seasonsEnabled()
  if Settings.is("seasons", "off") then return false end
  local cfg = Config.get().seasons
  if cfg and cfg.enabled == false then return false end
  return true
end

-- HOISTED. This sat below notifyEnabled(), which calls it. A Lua
-- `local function` is invisible above its own declaration, so the call
-- resolved to a nil global and threw -- taking the UI-mod banner
-- suppression with it and drawing a second route banner over the other
-- mod's. Fixed once before and reintroduced; a guard now pins it.
local function otherUiOwnsBanners()
  if Seasons._bannerOwner == "external" then return true end
  if not (mod and mod.find) then return false end
  local ids = {
    "gen3_battle_ui", "GEN3_BATTLE_UI",
    "kanto_companion", "KANTO_COMPANION",
    "colosseum_ui_overhaul", "Colosseum-Inspired-UI-Overhaul",
    "CRYSTAL_251", "crystal_251",
    "ds_fp_ceiling", "pokegear_cards",
  }
  for i = 1, #ids do
    local ok, found = pcall(function() return mod.find(ids[i]) end)
    if ok and found then
      Seasons._bannerOwner = "external"
      return true
    end
  end
  return false
end

local function notifyEnabled()
  if otherUiOwnsBanners() then return false end
  if Settings.is("seasonNotify", "off") then return false end
  local cfg = Config.get().seasons
  if cfg and cfg.notify == false then return false end
  return true
end

local function daysPerSeason()
  local cfg = Config.get().seasons
  local n = cfg and tonumber(cfg.daysPerSeason)
  if n and n >= 1 then return math.floor(n) end
  return 15
end

-- ROUTE_1 / PALLET_TOWN / INDIGO_PLATEAU -> "Route 1" / "Pallet Town" / ...
local function prettyMapName(mapId)
  if type(mapId) ~= "string" or mapId == "" then return nil end
  local s = mapId:gsub("_", " ")
  -- Title-case each word; keep short all-caps tokens (HM, SS) alone.
  s = s:gsub("(%S+)", function(w)
    if #w <= 2 and w == w:upper() then return w end
    return w:sub(1, 1):upper() .. w:sub(2):lower()
  end)
  return s
end


-- When another UI mod owns route/season banners, Weather FX must not draw its own.

local function placeNotifyEnabled()
  if otherUiOwnsBanners() then return false end
  if not seasonsEnabled() then return false end
  if Settings.is("seasonNotify", "off") then return false end
  local cfg = Config.get().seasons
  if cfg and cfg.notify == false then return false end
  if cfg and cfg.placeBanner == false then return false end
  return true
end

-- Called every frame with the current map id (from either pipeline).
-- Fires the place+season banner once on first overworld sighting this
-- session, and again whenever the map changes.
function Seasons.onMap(mapId)
  if type(mapId) ~= "string" or mapId == "" then return end
  local first = not Seasons._seenOverworld
  local changed = Seasons._lastMapId and Seasons._lastMapId ~= mapId
  if first or changed then
    Seasons.showPlace(mapId)
  end
  Seasons._seenOverworld = true
  Seasons._lastMapId = mapId
end

-- Queue the place+season banner shown on map entry / game entry.
-- Layout: location name on top, season underneath (or alone if no name).
-- Does not override an active "has begun" season-change headline; it only
-- attaches the place line under that message.
function Seasons.showPlace(mapId)
  if not placeNotifyEnabled() then return end
  local place = prettyMapName(mapId)
  if not place then return end
  local season = Seasons.TITLE[Seasons.id] or Seasons.id
  local changing = Seasons.notifyText
      and Seasons.notifyText:find("has begun", 1, true)
  if changing then
    Seasons.notifyPlace = place
  else
    Seasons.notifyPlace = place
    Seasons.notifyText = season
  end
  local cfg = Config.get().seasons
  local hold = (cfg and tonumber(cfg.notifySeconds)) or 3.5
  if Seasons.notifyT < hold then Seasons.notifyT = hold end
end

-- Month 1..12 -> season id, respecting hemisphere.
local function seasonFromMonth(month)
  local idx = NORTH_BY_MONTH[month] or 1
  if hemisphere() == "southern" then
    idx = SOUTH_OF[idx] or idx
  end
  return Seasons.IDS[idx]
end

-- Day-of-year 0..yearLen-1 -> season id (equal-length seasons).
local function seasonFromDayOfYear(day, yearLen)
  yearLen = math.max(4, yearLen or (daysPerSeason() * 4))
  local per = yearLen / 4
  local idx = math.floor((day % yearLen) / per) + 1
  if idx > 4 then idx = 4 end
  if hemisphere() == "southern" then
    idx = SOUTH_OF[idx] or idx
  end
  return Seasons.IDS[idx]
end

-- Resolve the current season from whichever clock TimeOfDay is using.
local function compute()
  if not seasonsEnabled() then
    return "SPRING", "off"
  end

  local cfg = Config.get().time
  local source = cfg and cfg.source or "system"

  -- Follow the live TOD source when possible so season and clock agree.
  local todSource = TOD.source
  if todSource == "system" or (source == "system" and todSource ~= "cycle"
      and todSource ~= "voxel" and todSource ~= "dramaless") then
    local ok, t = pcall(os.date, "*t")
    if ok and type(t) == "table" and type(t.month) == "number" then
      return seasonFromMonth(t.month), "system"
    end
  end

  -- Host clocks own the game-day serial as well as the hour. This keeps the
  -- season/year aligned with the clock the player sees instead of letting an
  -- unrelated Weather FX elapsed timer march through four seasons at fixed noon.
  local dayIndex
  if todSource == "voxel" or todSource == "dramaless" or todSource == "host-passive" then
    if TOD.gameDaySerial then
      dayIndex = math.floor(TOD.gameDaySerial() or 0)
    else
      -- Compatibility for older/simple clock providers used by add-ons/tests.
      local period=math.max(30,(cfg and cfg.cycleMinutes or 24)*60)
      dayIndex=math.floor((TOD.elapsed or 0)/period)
    end
    local yearLen = daysPerSeason() * 4
    return seasonFromDayOfYear(dayIndex, yearLen), "host"
  end

  -- Standalone accelerated/fixed clocks use TimeOfDay's monotonic game-day
  -- serial rather than elapsed/period. That serial counts visible midnight
  -- crossings, so editing GAME DAY LENGTH cannot teleport the season/year.
  if TOD.gameDaySerial then
    dayIndex = math.floor(TOD.gameDaySerial() or 0)
  else
    local period=math.max(30,(cfg and cfg.cycleMinutes or 24)*60)
    dayIndex=math.floor((TOD.elapsed or 0)/period)
  end
  local yearLen = daysPerSeason() * 4
  return seasonFromDayOfYear(dayIndex, yearLen), "cycle"
end

function Seasons.current()
  return Seasons.id
end

function Seasons.multiplier(def)
  if not seasonsEnabled() then return 1 end
  if not def then return 1 end
  local row = MULT[Seasons.id]
  if not row then return 1 end
  local m = 1
  if def.wet and row.wet then m = m * row.wet end
  if def.frozen and row.frozen then m = m * row.frozen end
  if def.sunny and row.sunny then m = m * row.sunny end
  if def.sandy and row.sandy then m = m * row.sandy end
  -- Fog is inferred from the channel table the same way biasFor does it.
  if Types.channel(def, "fog") > 0 and row.fog then m = m * row.fog end
  local specific=WEATHER_MULT[Seasons.id]
  local sm=specific and specific[tostring(def.id or ""):upper()]
  if sm~=nil then m=m*sm end
  return m
end

function Seasons.weatherMultiplier(id)
  local d=Types.get(id);return Seasons.multiplier(d)
end
function Seasons._setForTest(id) if MULT[tostring(id or ""):upper()] then Seasons.id=tostring(id):upper();return true end return false end

function Seasons.update(dt, mapId)
  dt = tonumber(dt) or 0
  if dt < 0 or dt ~= dt then dt = 0 end
  if dt > 0.25 then dt = 0.25 end

  local id, source = compute()
  Seasons.source = source

  if not Seasons._bootstrapped then
    -- First tick of a session: restore the last known season so a reload
    -- does not re-fire the season-change banner, then adopt the clock.
    local ok, stored = pcall(function()
      return mod.save:get("season", nil)
    end)
    if ok and type(stored) == "string" and MULT[stored] then
      Seasons._lastPersisted = stored
    end
    Seasons._bootstrapped = true
  end

  if id ~= Seasons.id then
    local previous = Seasons.id
    Seasons.id = id
    if Seasons._lastPersisted and Seasons._lastPersisted ~= id
        and notifyEnabled() and seasonsEnabled() then
      Seasons.notifyText = (Seasons.LABELS[id] or id) .. " has begun!"
      Seasons.notifyPlace = nil
      local cfg = Config.get().seasons
      Seasons.notifyT = (cfg and tonumber(cfg.notifySeconds)) or 3.5
    end
    Seasons._lastPersisted = id
    pcall(function() mod.save:set("season", id) end)
    if previous and previous ~= id then
      mod.log:info("season -> %s (%s)", id, source)
    end
  elseif not Seasons._lastPersisted then
    Seasons._lastPersisted = id
    pcall(function() mod.save:set("season", id) end)
  end

  -- Map tracking is also done from onMap (weather pipeline) so the place
  -- banner still fires when TIME is OFF.  Calling both is safe: the second
  -- pass sees the same map id and does nothing.
  if mapId then Seasons.onMap(mapId) end

  if Seasons.notifyT > 0 then
    Seasons.notifyT = Seasons.notifyT - dt
    if Seasons.notifyT <= 0 then
      Seasons.notifyT = 0
      Seasons.notifyText = nil
      Seasons.notifyPlace = nil
    end
  end
end

function Seasons.describe()
  if not seasonsEnabled() then return "OFF" end
  local hemi = (hemisphere() == "southern") and "S" or "N"
  return ("%s/%s"):format(Seasons.id, hemi)
end

-- Draw the banner.  Called from the HUD hook; returns true if it drew.
-- Two layouts:
--   place + season  ->  "Pallet Town"  (top) / "Summer" (underneath)
--   season change   ->  "WINTER has begun!"  (single line, optional place)
-- Uses the host font so it matches the debug readout and other HUD text.
function Seasons.drawNotify()
  if otherUiOwnsBanners() then return false end
  -- Live setting authority: turning SEASON NOTE OFF while a banner is already
  -- on screen hides it immediately rather than waiting for its old timer.
  if Settings.is("seasonNotify", "off") then
    Seasons.notifyT = 0
    Seasons.notifyText = nil
    Seasons.notifyPlace = nil
    return false
  end
  if Seasons.notifyT <= 0 then return false end
  if not Seasons.notifyText and not Seasons.notifyPlace then return false end
  if not (love and love.graphics) then return false end

  local cfg = Config.get().seasons
  local hold = (cfg and tonumber(cfg.notifySeconds)) or 3.5
  local t = Seasons.notifyT
  -- Fade in over the first 0.4s, hold, fade out over the last 0.6s.
  local alpha = 1
  local fadeIn, fadeOut = 0.4, 0.6
  if t > hold - fadeIn then
    alpha = math.max(0, (hold - t) / fadeIn)
  elseif t < fadeOut then
    alpha = math.max(0, t / fadeOut)
  end
  if alpha <= 0.02 then return false end

  local font = love.graphics.getFont()
  local th = font:getHeight()
  local padX, padY, gap = 12, 6, 2

  local place = Seasons.notifyPlace
  local line2 = Seasons.notifyText
  -- Place banner: location on top, season underneath.
  -- Season-change: headline on top, optional place underneath.
  local line1, sub
  if place and line2 and not line2:find("has begun", 1, true) then
    line1, sub = place, line2
  elseif line2 and line2:find("has begun", 1, true) then
    line1, sub = line2, place
  else
    line1, sub = line2 or place, nil
  end

  local w1 = font:getWidth(line1 or "")
  local w2 = sub and font:getWidth(sub) or 0
  local boxW = math.max(w1, w2) + padX * 2
  local lines = sub and 2 or 1
  local boxH = padY * 2 + th * lines + (lines > 1 and gap or 0)
  local sw = love.graphics.getWidth()
  local x = math.floor((sw - boxW) * 0.5)
  local y = 18

  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  love.graphics.setColor(0.05, 0.08, 0.14, 0.72 * alpha)
  love.graphics.rectangle("fill", x, y, boxW, boxH, 3, 3)
  love.graphics.setColor(0.85, 0.92, 1.0, 0.95 * alpha)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, boxW - 1, boxH - 1, 3, 3)

  -- Location (or season-change headline) in white; season subtitle softer.
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.print(line1, x + math.floor((boxW - w1) * 0.5), y + padY)
  if sub then
    love.graphics.setColor(0.75, 0.88, 1.0, 0.95 * alpha)
    love.graphics.print(sub, x + math.floor((boxW - w2) * 0.5),
      y + padY + th + gap)
  end
  love.graphics.setColor(prevR, prevG, prevB, prevA)
  return true
end

return Seasons
