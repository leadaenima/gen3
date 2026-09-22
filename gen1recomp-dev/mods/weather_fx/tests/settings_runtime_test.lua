-- Behavioral test for current Gen1Recomp option semantics.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name) end
end

local values = { always = "off" }
local defined, optionChanged
local P = { levelValue = 1 }
function P.setLevel(id, level) P.levelValue = level end
function P.syncOptions(_) end
package.loaded["src.render.Pipelines"] = P
package.loaded["src.core.Game"] = { save = { options = {} } }

local Types = {
  PINNED = { "RAIN_LIGHT", "SNOW_LIGHT" },
  byId = { RAIN_LIGHT = true, SNOW_LIGHT = true },
}
function Types.get(id)
  local defs = {
    RAIN_LIGHT = { id = "RAIN_LIGHT", label = "LIGHT RAIN" },
    SNOW_LIGHT = { id = "SNOW_LIGHT", label = "LIGHT SNOW" },
  }
  return defs[id]
end
local WeatherState = { LEVEL_IDS = { false, "AUTO", "RAIN_LIGHT", "SNOW_LIGHT" } }

local mod = {
  id = "weather_fx",
  options = {
    define = function(self, rows) defined = rows; return true end,
    get = function(self, key) return values[key] end,
    -- Deliberately NO set(): this matches the current public API contract.
  },
  events = {
    on = function(self, name, fn)
      if name == "mod.options_changed" then optionChanged = fn end
    end,
  },
  log = { info = function() end, warn = function() end },
}
local V = { mod = mod }
function V.require(name)
  if name == "Types" then return Types end
  if name == "WeatherState" then return WeatherState end
  error("unexpected require " .. tostring(name))
end

local chunk = assert(loadfile("lib/Settings.lua"))
local Settings = chunk(V)
check(Settings.define() == true, "Settings.define succeeds")
check(type(defined) == "table" and  #defined == 78, "78 core settings registered")
check(type(optionChanged) == "function", "mod.options_changed subscribed")
local byKey={}
for _,row in ipairs(defined or {}) do byKey[row.key]=row end
local sfxHelp=((byKey.sfx or {}).help or ''):lower()
check(sfxHelp:find('wind',1,true)~=nil and sfxHelp:find('thunder',1,true)~=nil,
  'WEATHER SFX help describes live rain/wind/thunder pipeline')
local qualityChoices={}
for _,c in ipairs((byKey.quality or {}).choices or {}) do qualityChoices[c[2]]=true end
check(qualityChoices.max and qualityChoices.high and qualityChoices.medium and qualityChoices.low and qualityChoices.potato,
  'QUALITY exposes MAX/HIGH/MEDIUM/LOW/POTATO manual tiers')

-- Every declared choice must round-trip to its EXACT canonical stored value,
-- and the display label must normalize back to that same value. This catches
-- settings that appear in the UI but feed an invalid representation downstream.
for _, row in ipairs(defined or {}) do
  local old = values[row.key]
  for _, choice in ipairs(row.choices or {}) do
    values[row.key] = choice[2]
    check(Settings.get(row.key) == choice[2], row.key .. " stored value round-trip " .. tostring(choice[2]))
    values[row.key] = choice[1]
    check(Settings.get(row.key) == choice[2], row.key .. " label maps to stored value " .. tostring(choice[1]))
  end
  values[row.key] = old
end

-- Derived helper semantics: the UI value has to reach the numeric/boolean
-- behavior the runtime consumes, not merely survive Settings.get().
local function setv(k, v) values[k] = v end
setv("intensity", "soft"); check(math.abs(Settings.intensity() - 0.45) < 0.0001, "INTENSITY SOFT maps to 0.45")
setv("intensity", "normal"); check(Settings.intensity() == 1.0, "INTENSITY NORMAL maps to 1.0")
setv("intensity", "heavy"); check(math.abs(Settings.intensity() - 1.50) < 0.0001, "INTENSITY HEAVY maps to 1.50")
setv("intensity", "auto"); check(Settings.intensity() == 1.0, "INTENSITY AUTO leaves base scale for family oscillator")

setv("rainIntensity", "off"); check(Settings.rainIntensity() == 0 and Settings.rainOff(), "RAIN INTENSITY OFF is a hard zero")
setv("rainIntensity", "100"); check(Settings.rainIntensity() == 1.0, "RAIN INTENSITY 100% is neutral")
setv("rainIntensity", "200"); check(Settings.rainIntensity() == 2.0, "RAIN INTENSITY 200% is a true 2x amount multiplier")
setv("windIntensity", "25"); check(Settings.windIntensity() == 0.25, "WIND INTENSITY 25% maps to quarter strength")
setv("windIntensity", "100"); check(Settings.windIntensity() == 1.0, "WIND INTENSITY 100% is neutral")
setv("windIntensity", "200"); check(Settings.windIntensity() == 2.0, "WIND INTENSITY 200% maps to double gust strength")
setv("lightningFlash", "off"); check(Settings.lightningFlashScale() == 0, "LIGHTNING FLASH OFF removes illumination")
setv("lightningFlash", "low"); check(Settings.lightningFlashScale() == 0.5, "LIGHTNING FLASH LOW maps to 50%")
setv("lightningFlash", "high"); check(Settings.lightningFlashScale() == 1.35, "LIGHTNING FLASH HIGH maps to 135%")
setv("lightningFrequency", "rare"); check(Settings.lightningFrequencyScale() == 0.45, "LIGHTNING FREQUENCY RARE maps to 45% cadence")
setv("lightningFrequency", "normal"); check(Settings.lightningFrequencyScale() == 1.0, "LIGHTNING FREQUENCY NORMAL preserves authored cadence")
setv("lightningFrequency", "extreme"); check(Settings.lightningFrequencyScale() == 2.25, "LIGHTNING FREQUENCY EXTREME maps to 225% cadence")
setv("screenEffects", "off"); check(Settings.screenEffectsScale() == 0, "WEATHER SCREEN EFFECTS OFF removes screen-only presentation")
setv("screenEffects", "reduced"); check(Settings.screenEffectsScale() == 0.5, "WEATHER SCREEN EFFECTS REDUCED maps to 50%")
setv("screenEffects", "full"); check(Settings.screenEffectsScale() == 1.0, "WEATHER SCREEN EFFECTS FULL preserves 8.1.81 presentation")
setv("tornadoDuration", "short"); check(Settings.tornadoDurationScale() == 0.5, "TORNADO DURATION SHORT maps to half mature roam")
setv("tornadoDuration", "normal"); check(Settings.tornadoDurationScale() == 1.0, "TORNADO DURATION NORMAL preserves mature roam")
setv("tornadoDuration", "long"); check(Settings.tornadoDurationScale() == 1.75, "TORNADO DURATION LONG maps to 175% mature roam")
setv("nightSkyBrightness", "low"); check(Settings.nightSkyBrightnessScale() == 0.65, "NIGHT SKY BRIGHTNESS LOW maps to 65%")
setv("nightSkyBrightness", "normal"); check(Settings.nightSkyBrightnessScale() == 1.0, "NIGHT SKY BRIGHTNESS NORMAL preserves 8.1.81 sky")
setv("nightSkyBrightness", "high"); check(Settings.nightSkyBrightnessScale() == 1.3, "NIGHT SKY BRIGHTNESS HIGH maps to 130%")
setv("puddles", "off"); check(Settings.puddleAmountScale() == 0, "WET GROUND OFF maps to zero visible wetness")
setv("puddles", "low"); check(Settings.puddleAmountScale() == 0.5, "WET GROUND LOW maps to 50%")
setv("puddles", "on"); check(Settings.puddleAmountScale() == 1.0, "WET GROUND NORMAL keeps legacy ON token and exact strength")
setv("puddles", "high"); check(Settings.puddleAmountScale() == 1.35, "WET GROUND HIGH maps to 135%")
setv("stormDarkness", "off"); check(Settings.stormDarknessScale() == 0, "STORM DARKNESS OFF removes Weather FX darkening")
setv("stormDarkness", "high"); check(Settings.stormDarknessScale() == 1.35, "STORM DARKNESS HIGH maps to 135%")
setv("tornadoPickup", "off"); check(Settings.tornadoPickupChance() == 0, "TORNADO PLAYER PICKUP OFF is zero chance")
setv("tornadoPickup", "rare"); check(math.abs(Settings.tornadoPickupChance() - 0.03) < 0.0001, "TORNADO PLAYER PICKUP RARE is 3%")
setv("tornadoPickup", "normal"); check(math.abs(Settings.tornadoPickupChance() - 0.10) < 0.0001, "TORNADO PLAYER PICKUP NORMAL is 10%")
setv("tornadoPickup", "frequent"); check(math.abs(Settings.tornadoPickupChance() - 0.25) < 0.0001, "TORNADO PLAYER PICKUP FREQUENT is 25%")
setv("thunderVolume", "25"); check(Settings.thunderVolumeScale() == 0.25, "THUNDER VOLUME 25% maps correctly")
setv("thunderVolume", "100"); check(Settings.thunderVolumeScale() == 1.0, "THUNDER VOLUME 100% is neutral")
setv("thunderVolume", "150"); check(Settings.thunderVolumeScale() == 1.5, "THUNDER VOLUME 150% maps correctly")

setv("snowIntensity", "off"); check(Settings.snowIntensity() == 0 and Settings.snowOff(), "SNOW INTENSITY OFF is a hard zero")
setv("snowIntensity", "100"); check(Settings.snowIntensity() == 1.0, "SNOW INTENSITY 100% is neutral")
setv("snowIntensity", "500"); check(Settings.snowIntensity() == 5.0, "SNOW INTENSITY 500% is a true 5x multiplier")
setv("snowAccumulation", "off"); check(not Settings.snowAccumulationEnabled(), "SNOW ACCUMULATION OFF disables persistent buildup")
setv("snowAccumulation", "on"); check(Settings.snowAccumulationEnabled(), "SNOW ACCUMULATION ON enables persistent buildup")
setv("weatherRenderDistance", "25"); check(Settings.weatherRenderDistanceScale() == 0.25, "3D WEATHER DISTANCE 25% maps to quarter voxel reach")
setv("weatherRenderDistance", "100"); check(Settings.weatherRenderDistanceScale() == 1.0, "3D WEATHER DISTANCE 100% maps to full voxel reach")

setv("fogIntensity", "off"); check(Settings.fogIntensity() == 0 and Settings.fogOff(), "FOG INTENSITY OFF is a hard zero")
setv("fogIntensity", "100"); check(Settings.fogIntensity() == 1, "FOG INTENSITY 100% is neutral")
setv("fogIntensity", "500"); check(Settings.fogIntensity() == 20, "FOG INTENSITY 500% reaches extreme curve")
setv("sandIntensity", "off"); check(Settings.sandIntensity() == 0 and Settings.sandOff(), "SAND INTENSITY OFF is a hard zero")
setv("sandIntensity", "500"); check(Settings.sandVisibility() == 0.25, "SAND INTENSITY 500% maps to 25% visibility")
setv("dustIntensity", "off"); check(Settings.dustIntensity() == 0 and Settings.dustOff(), "DUST INTENSITY OFF is a hard zero")
setv("dustIntensity", "500"); check(Settings.dustVisibility() == 0.25, "DUST INTENSITY 500% maps to 25% visibility")

for value, want in pairs({ normal=1.0, ["2x"]=0.50, ["4x"]=0.25, ["10x"]=0.10, ["20x"]=0.05 }) do
  setv("speed", value); check(math.abs(Settings.speedScale() - want) < 0.0001, "WEATHER DURATION " .. value .. " maps correctly")
end
for value, want in pairs({ off=0, rare=1, normal=3, often=7 }) do
  setv("exotic", value); check(Settings.exoticScale() == want, "RARE WEATHER " .. value .. " maps correctly")
end

setv("clouds", "off"); check(Settings.cloudsOn() == false, "CLOUDS OFF is false")
setv("clouds", "on"); check(Settings.cloudsOn() == true, "CLOUDS ON is true")
setv("cloudHeight", "raised"); check(Settings.cloudHeightScale() == 1.5, "CLOUD HEIGHT RAISED is 150 percent")
setv("cloudHeight", "original"); check(Settings.cloudHeightScale() == 1.0, "CLOUD HEIGHT ORIGINAL restores pre-8.1.22 altitude")
setv("cloudDensity", "low"); check(Settings.cloudDensityScale() == 0.72 and Settings.cloudDensityGateBias() == 0.14, "CLOUD DENSITY LOW opens cells and reduces puffs")
setv("cloudDensity", "normal"); check(Settings.cloudDensityScale() == 1.0 and Settings.cloudDensityGateBias() == 0, "CLOUD DENSITY NORMAL is exact no-op")
setv("cloudDensity", "veryhigh"); check(Settings.cloudDensityScale() == 1.45 and Settings.cloudDensityGateBias() == -0.14, "CLOUD DENSITY VERY HIGH fills cells and increases puffs")
setv("leafColor", "orange"); check(Settings.leafColor() == "orange", "LEAF COLOR reaches renderer value")
setv("snowShape", "ball"); check(Settings.snowShape() == "ball", "SNOW SHAPE BALL reaches renderer value")

for value, want in pairs({ off=0, subtle=0.5, full=1 }) do
  setv("battles", value); check(Settings.battleScale() == want, "BATTLES " .. value .. " maps correctly")
end
setv("battles", "off"); check(Settings.battleAnimOn() == false, "BATTLE WEATHER OFF is the single visual kill switch")
setv("battles", "full"); check(Settings.battleAnimOn() == true, "BATTLE WEATHER FULL enables battle visuals")
setv("battleDamage", "off"); check(Settings.battleDamageOn() == false, "BATTLE WEATHER DMG OFF is false")
setv("battleDamage", "on"); check(Settings.battleDamageOn() == true, "BATTLE WEATHER DMG ON is true")

setv("present", "2d"); check(Settings.presentMode() == "2d" and Settings.force2dPresent() and not Settings.allow3dPresent(), "WX PRESENT 2D forces 2D")
setv("present", "3d"); check(Settings.presentMode() == "3d" and not Settings.force2dPresent() and Settings.allow3dPresent(), "WX PRESENT 3D allows 3D")
setv("present", "auto"); check(Settings.allow3dPresent(), "WX PRESENT AUTO allows 3D fallback path")

setv("debug", "simple"); check(Settings.debugHudMode() == "simple", "DEBUG HUD SIMPLE maps correctly")
setv("debug", "on"); check(Settings.debugHudMode() == "full", "legacy DEBUG HUD ON aliases FULL")
setv("debug", "off"); check(not Settings.debugHudOn(), "DEBUG HUD OFF disables HUD")
setv("debugRain", "on"); check(Settings.debugRain({ get=function() return { debugRain=false } end }), "DEBUG RAIN ON overrides config false")
setv("debugRain", "off"); check(not Settings.debugRain({ get=function() return { debugRain=false } end }), "DEBUG RAIN OFF stays off when config false")

-- WX Pokémon is intentionally absent from the core settings after the split.
check(Settings.SCHEMA and #Settings.SCHEMA == 78, "core schema includes current weather, pause-menu, cloud-bank, advanced, audio and gameplay settings without removed RAVE controls")

-- WEATHER row -> engine ladder works without mod.options:set().
values.always = "RAIN_LIGHT"
optionChanged({ mod = "weather_fx", key = "always", value = "RAIN_LIGHT" })
check(P.levelValue == 2, "WEATHER mod row pushes engine ladder")
check(Settings.alwaysWeather() == "RAIN_LIGHT", "WEATHER runtime mirror follows menu")

-- Engine ladder -> runtime authority even though saved duplicate row is stale and
-- cannot be written through the public mod.options API.
Settings._menuPinDirty = false
Settings.syncWeatherFromLadder(1) -- AUTO
check(values.always == "RAIN_LIGHT", "test really has stale saved duplicate row")
check(Settings.alwaysWeather() == nil, "AUTO ladder overrides stale saved WEATHER row")

print(("settings runtime: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
