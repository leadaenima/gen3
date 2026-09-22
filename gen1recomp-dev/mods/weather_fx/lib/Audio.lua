-- WEATHER AUDIO.
--
-- A looping bed per weather family, cross-faded when the weather turns,
-- with the volume following the eased channel so a storm swells as it
-- arrives rather than snapping on -- and a thunder one-shot fired from the
-- strike scheduler so the crack lands with the flash.
--
-- =====================================================================
-- WHAT IS AND IS NOT COVERED, STATED UP FRONT
-- =====================================================================
--
-- The looping precipitation BEDS are rain/storm recordings, so only weather
-- that actually contains rain is assigned one.  Wind is a separate layer and
-- gives gust-heavy snow, sand, ash and strong-wind weather an appropriate
-- voice without pretending rain is falling.  Thunder is a third, independent
-- one-shot layer. Quiet weather such as fog/light snow can remain silent.
--
-- =====================================================================
-- WHY love.audio DIRECTLY
-- =====================================================================
--
-- The engine's audio registry is built around the game's own music and
-- cries -- tracks it owns, selected through `music.select` and mixed at
-- the engine's volume.  A weather bed is neither: it plays UNDER whatever
-- music is running, follows a channel value rather than a track change,
-- and has to duck and swell continuously.  Driving `love.audio` directly
-- keeps that entirely inside this mod, where it can be switched off
-- without touching anything the engine mixes.
--
-- The cost is that the engine's own volume slider does not reach it, so
-- this carries its own -- `WEATHER SFX` in the mod manager, OFF included.
--
-- =====================================================================
-- CROSS-FADE, NOT SWAP
-- =====================================================================
--
-- Two slots, never one.  A weather change fades the outgoing bed down
-- while the incoming one comes up, over the same seconds the visual
-- transition takes, so the ear and the eye agree about when the storm
-- arrived.  Swapping the source instead would produce a click and a
-- discontinuity exactly at the moment the player is looking up.

local V = ...
local mod = V.mod
local Types = V.require("Types")
local Config = V.require("Config")
local Settings = V.require("Settings")
local Scene = V.require("Scene")
local State = V.require("WeatherState")
local Lightning = V.require("Lightning")
local Legendary = V.require("Legendary")
local WindEngineCached = false
local DistantWeatherCached = false
local function distantWeather()
  if DistantWeatherCached then return DistantWeatherCached end
  local ok,m=pcall(V.require,"DistantWeather")
  if ok and m then DistantWeatherCached=m;return m end
  return nil
end
local function windEngine()
  if WindEngineCached then return WindEngineCached end
  local ok, m = pcall(V.require, "WindEngine")
  if ok and m then WindEngineCached = m; return m end
  return nil
end

local Audio = {}

Audio.DIR = "assets/sounds/"

-- Which bed a weather uses, and how loud at full channel.  `nil` means
-- silent, which is most of the catalogue and is a decision rather than a
-- gap -- see the header.
--
-- Chosen by the weather's own id so the mapping is readable, with a
-- channel-driven fallback for anything unlisted (a new rain type gets rain
-- without being named here).
Audio.BEDS = {
  RAIN_LIGHT  = { file = "rain",        gain = 0.55 },
  RAIN        = { file = "rain",        gain = 0.55 },
  RAIN_HEAVY  = { file = "rain_heavy",  gain = 0.75 },
  HEAVY_RAIN  = { file = "heavy_storm", gain = 0.95 },
  STORM       = { file = "storm",       gain = 0.85 },
  -- GALE has no electrical activity. Use rain-only bed + the separate
  -- WindEngine layer so a loop with thunder texture can never imply lightning.
  GALE        = { file = "rain_heavy",  gain = 0.70 },
  SLEET       = { file = "rain",        gain = 0.4 },
  PRIMAL_RAIN = { file = "heavy_storm", gain = 1.0 },
  PSYSTORM    = { file = "storm",       gain = 0.65 },
  DRAGONSTORM = { file = "storm",       gain = 0.8 },
  -- THUNDERSNOW: EXPLICITLY NO BED.
  --
  -- `false` means "this weather is deliberately silent", as distinct from nil,
  -- which means "unlisted, work it out from the channels".
  --
  -- It used to be the `storm` bed, which is a RAIN recording. Nothing falls as
  -- rain in a thundersnow -- the catalogue entry is snow-only -- so the bed was
  -- describing weather that is not happening. It went unnoticed while a
  -- separate bug stopped the bed a frame after it started; fixing that in
  -- 4.30.28 made it audible and it sounded like rain.
  --
  -- There is no snow bed to swap in (assets/sounds has rain, rain_heavy,
  -- storm, heavy_storm and wind, and nothing else), and that is fine: snow is
  -- close to silent, and THUNDERSNOW carries gust = 0.9, so the WIND layer
  -- gives it a voice. Thunder is a one-shot gated by strikeWeatherId() and is
  -- entirely independent of the bed, so the claps are unaffected.
  THUNDERSNOW = false,
  -- Clear / non-rain: no bed (wind layer may still run from gust)
  CLEAR       = nil,
  SUNNY       = nil,
  FOG         = nil,
  MIST        = nil,
}

Audio.THUNDER = { "thunder_clap", "thunder_roll" }

-- THUNDER FOR WEATHERS WITH NO RAIN IN THEM.
--
-- `thunder_roll` is a SIXTY SECOND sample -- 1.88 MB against thunder_clap's
-- 224 KB, and longer than the rain beds themselves. It is a sustained rumble
-- with storm ambience under it, which is fine layered over a rain bed and is
-- indistinguishable from rain when there is no bed beneath it.
--
-- It is picked at random, so on THUNDERSNOW the first strike might be a clap
-- and the second a roll -- and from that point a minute of rain-like noise is
-- playing. That is "the second thunderclap starts the rain sounds", and it is
-- also why it sounded like it came back "after about a minute": that is the
-- sample looping round on a later strike.
--
-- One-shots are deliberately not stopped by the bed logic (4.30.28, so a clap
-- is never cut mid-sound), which is what lets it run its full length.
--
-- So: dry-thunder weathers get the short clap only.
Audio.THUNDER_DRY = { "thunder_clap" }

-- THUNDER EVENT / VOICE POLICY ------------------------------------------
--
-- Every visible world-space bolt gets its own thunder event.  The visual
-- scheduler may create one event containing several independent 3D bolts; the
-- voxel renderer publishes every bolt distance onto Lightning and Audio waits
-- briefly for that real geometry before scheduling sound.  In 2D, where no
-- world-space distance exists, Audio falls back to one plausible distant event.
--
-- Thunder propagation uses the speed of sound rather than an arbitrary audio
-- cooldown.  Existing one-shots are independent Sources and may overlap; a new
-- bolt never has to wait for the previous file to finish.
Audio.THUNDER_MIX = {
  maxVoices = 48,       -- safety ceiling; PSYSTORM averages well below this
  maxRolls = 1,         -- never stack multiple minute-long ambient rolls
  denseRate = 16.0,     -- dense/burst events always use the short clap sample
  speedOfSound = 343.0, -- world units/second (WorldLightning ranges behave as m)
  maxDelay = 4.0,
  fallbackGrace = 0.12, -- allow the 3D draw pass one frame to publish distances
  fallbackDistance = 320.0,
  nearDistance = 90.0,
  farDistance = 900.0,
  farGain = 0.55,       -- far thunder is quieter, but never disappears

  -- PSYSTORM needs a different acoustic shape from an ordinary thunderstorm.
  -- A multi-bolt psychic burst played as several identical full-pitch clap
  -- transients sounds like gunfire.  Keep one softened electrical crack for the
  -- nearest bolt, turn the remaining bolts into darker/lower thunder bodies,
  -- and add one delayed low rumble to give the burst weight and decay.
  psychicCrackGain = 0.88,
  psychicBoomGain = 0.68,
  psychicRumbleGain = 0.48,
  psychicCrackPitchMin = 0.84,
  psychicCrackPitchMax = 0.93,
  psychicBoomPitchMin = 0.68,
  psychicBoomPitchMax = 0.79,
  psychicRumblePitchMin = 0.58,
  psychicRumblePitchMax = 0.66,
  psychicCrackHighGain = 0.40,
  psychicBoomHighGain = 0.22,
  psychicRumbleHighGain = 0.12,
  psychicSecondaryStaggerMin = 0.035,
  psychicSecondaryStaggerMax = 0.105,
  psychicRumbleDelayMin = 0.16,
  psychicRumbleDelayMax = 0.28,

  -- Distance changes timbre, not just volume. Past this range the sharp
  -- electrical crack is physically filtered away and replaced by a broad low
  -- boom plus a delayed rolling body. This is the key anti-gunfire behavior.
  psychicFarStart = 420.0,
  psychicFarFull = 900.0,
  psychicFarBoomGain = 0.78,
  psychicFarBoomPitchMin = 0.50,
  psychicFarBoomPitchMax = 0.64,
  psychicFarBoomHighGain = 0.055,
  psychicFarTailGain = 0.52,
  psychicFarTailPitchMin = 0.40,
  psychicFarTailPitchMax = 0.53,
  psychicFarTailHighGain = 0.035,
  psychicFarTailDelayMin = 0.26,
  psychicFarTailDelayMax = 0.62,
}
Audio._audioClock = 0
Audio._lastThunderAt = -1e9 -- retained for old save/debug compatibility only
Audio._lastStrikeSerial = 0
Audio._oneshots = {}
Audio._oneshotMeta = setmetatable({}, { __mode = "k" })
Audio._pendingStrikeEvents = {}
Audio._scheduledThunder = {}
Audio._psychicBoltCounter = 0 -- every second PSYSTORM bolt is audible
Audio.THUNDER_DURATION = {
  thunder_clap = 7.5,
  thunder_roll = 60.5,
  thunder_zapdos = 5.8,
}

local _AcousticModel=nil
local function acousticGain(kind)
  if _AcousticModel==nil then local ok,m=pcall(V.require,"AcousticModel"); _AcousticModel=(ok and m) or false end
  if _AcousticModel and _AcousticModel.gain then local ok,v=pcall(_AcousticModel.gain,kind); if ok then return tonumber(v) or 1 end end
  return 1
end

local function clamp01(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function smooth01(v)
  v = clamp01(v)
  return v * v * (3 - 2 * v)
end

local function thunderDistanceDelay(distance)
  local mix = Audio.THUNDER_MIX or {}
  local d = math.max(0, tonumber(distance) or tonumber(mix.fallbackDistance) or 320)
  local speed = math.max(1, tonumber(mix.speedOfSound) or 343)
  return math.min(math.max(0, tonumber(mix.maxDelay) or 4), d / speed)
end
Audio.thunderDistanceDelay = thunderDistanceDelay

local function thunderDistanceGain(distance)
  local mix = Audio.THUNDER_MIX or {}
  local nearD = math.max(0, tonumber(mix.nearDistance) or 90)
  local farD = math.max(nearD + 1, tonumber(mix.farDistance) or 900)
  local farGain = math.max(0.05, math.min(1, tonumber(mix.farGain) or 0.55))
  local d = math.max(0, tonumber(distance) or tonumber(mix.fallbackDistance) or 320)
  local t = smooth01((d - nearD) / (farD - nearD))
  return 1 - (1 - farGain) * t
end
Audio.thunderDistanceGain = thunderDistanceGain

-- WIND IS ITS OWN LAYER, not another bed.
--
-- A bed is chosen -- a weather has one or it has none -- and the two slots
-- cross-fade between them.  Wind is not like that: a gale and a downpour
-- happen at once, and a blizzard is nothing BUT wind.  So it plays
-- alongside whatever bed is running, at a volume taken straight from the
-- `gust` channel, which means it swells and drops with the same oscillator
-- that leans the rain and drifts the snow.
--
-- This also gives most of the previously-silent weathers a voice without
-- misrepresenting them: a blizzard, a sandstorm, an ashfall and the strong
-- winds all carry gust, and wind is what they actually sound like.  Fog
-- has none and stays silent, which is correct -- fog is quiet.
Audio.WIND = { file = "wind", gain = 0.6 }

-- INDOOR ACOUSTICS -----------------------------------------------------
--
-- Lower volume alone sounds like the outdoor mix with the fader pulled down.
-- A building also removes high-frequency detail and softens transients, so
-- weather heard through walls/windows needs an occlusion filter. Love2D exposes
-- this through Source:setFilter on hosts with OpenAL EFX support. Some
-- Gen1Recomp/Love builds do not expose EFX, so every filter operation is
-- protected: unsupported hosts keep the existing volume attenuation instead of
-- losing weather audio entirely.
--
-- `highgain` is the amount of high-frequency energy that survives the low-pass
-- filter (1 = outdoor/unfiltered, smaller = more muffled). These are deliberately
-- different per layer: thunder loses the most sharp crack, wind loses hiss, and
-- rain keeps a little more texture so the player can still tell that it is raining.
Audio.INDOOR_ACOUSTICS = {
  transitionSeconds = 0.45,
  -- 8.1.52: walls should color the weather, not erase it. Rain is kept the
  -- brightest because its intelligibility lives heavily in the high-frequency
  -- texture; wind is darker; thunder keeps the strongest permitted muffling.
  rainHighGain = 0.55,
  windHighGain = 0.45,
  thunderHighGain = 0.40,
  minRetainedGain = 0.40, -- maximum building-only attenuation/muffling = 60%
}
Audio._indoorMix = 0
Audio._indoorState = nil
Audio._filterState = setmetatable({}, { __mode = "k" })
Audio._frameAudioCfg = nil
local function audioCfg()
  if Audio._frameAudioCfg then return Audio._frameAudioCfg end
  local c=Config.get(); return (c and c.audio) or {}
end
local function setVolumeIfChanged(src, owner, vol)
  if not (src and src.setVolume) then return end
  vol=math.max(0,math.min(1,tonumber(vol) or 0))
  local last=owner and owner._lastVolume
  if last==nil or math.abs(last-vol)>=0.0015 then src:setVolume(vol); if owner then owner._lastVolume=vol end end
end
local function setPitchIfChanged(src, owner, pitch)
  if not (src and src.setPitch) then return end
  pitch=tonumber(pitch) or 1; local last=owner and owner._lastPitch
  if last==nil or math.abs(last-pitch)>=0.001 then src:setPitch(pitch); if owner then owner._lastPitch=pitch end end
end

local function indoorTarget()
  return (Scene.now and Scene.now.indoors) and 1 or 0
end

local function stepIndoorMix(dt)
  local target = indoorTarget()
  local cfg = audioCfg()
  local sec = tonumber(cfg.indoorTransition)
      or tonumber(Audio.INDOOR_ACOUSTICS.transitionSeconds) or 0.45
  sec = math.max(0.05, sec)
  local a = tonumber(Audio._indoorMix) or 0

  -- On the first audio frame, adopt the current room immediately. This avoids a
  -- save loaded inside a house briefly blasting the outdoor mix. After that,
  -- doorway/map transitions are smoothed.
  if Audio._indoorState == nil then
    a = target
    Audio._indoorState = target
  else
    local step = math.min(1, math.max(0, (tonumber(dt) or 0) / sec))
    if a < target then a = math.min(target, a + step)
    elseif a > target then a = math.max(target, a - step) end
    Audio._indoorState = target
  end
  Audio._indoorMix = a
  return a
end

local function indoorHighGain(kind, mix)
  mix = math.max(0, math.min(1, tonumber(mix) or 0))
  local cfg = audioCfg()
  local key = ({ rain = "indoorRainHighGain", wind = "indoorWindHighGain",
                 thunder = "indoorThunderHighGain" })[kind]
  local defaults = {
    rain = Audio.INDOOR_ACOUSTICS.rainHighGain,
    wind = Audio.INDOOR_ACOUSTICS.windHighGain,
    thunder = Audio.INDOOR_ACOUSTICS.thunderHighGain,
  }
  local floor = tonumber(key and cfg[key]) or defaults[kind] or 0.4
  -- Hard contract: entering a building alone may never remove more than 60%
  -- of a weather layer's high-frequency energy. This also upgrades old user
  -- configs that still contain the pre-8.1.52 0.20/0.12/0.08 values.
  local retained = tonumber(Audio.INDOOR_ACOUSTICS.minRetainedGain) or 0.40
  floor = math.max(retained, math.min(1, floor))
  return 1 - (1 - floor) * mix
end

local function applyIndoorFilter(src, kind, mix)
  if not src or type(src.setFilter) ~= "function" then return false end
  local state = Audio._filterState[src]
  if state == false then return false end -- backend already told us EFX is unavailable

  mix = math.max(0, math.min(1, tonumber(mix) or 0))
  if mix <= 0.001 then
    if state == "clear" then return true end
    -- Love2D clears a Source filter when setFilter is called without arguments.
    local ok = pcall(function() src:setFilter() end)
    if ok then
      Audio._filterState[src] = "clear"
      return true
    end
    Audio._filterState[src] = false
    return false
  end

  local high = indoorHighGain(kind, mix)
  if type(state) == "table" and state.kind == kind
      and math.abs((state.high or -1) - high) < 0.002 then
    return true
  end

  local ok, supported = pcall(function()
    return src:setFilter({ type = "lowpass", volume = 1.0, highgain = high })
  end)
  -- Source:setFilter returns false when the host/backend cannot apply EFX. A
  -- successful pcall is therefore not enough to claim the source is filtered.
  if not ok or supported == false then
    Audio._filterState[src] = false
    return false
  end
  Audio._filterState[src] = { kind = kind, high = high }
  return true
end

Audio.applyIndoorFilter = applyIndoorFilter
Audio.indoorHighGain = indoorHighGain

-- Which wind.  Grit blowing across a desert does not sound like wind
-- through trees, and a sandstorm that borrowed the ordinary loop would be
-- the same lie as a blizzard borrowing the rain.
--
-- Matched by capability tag rather than by id, so a new sandy weather --
-- ashfall already, and whatever comes next -- gets the right wind without
-- being named here.
function Audio.windFileFor(def)
  if def and def.sandy then return "wind_desert" end
  return Audio.WIND.file
end

-- A weather with no entry still gets rain if it is genuinely raining:
-- the id table is for tuning, not for gatekeeping.
local function bedFor(def)
  if not def then return nil end
  local id = def.id
  if Audio.BEDS[id] ~= nil then
    -- `false` is the explicit-silence sentinel; return nil so callers see
    -- "no bed" rather than a table.
    if Audio.BEDS[id] == false then return nil end
    return Audio.BEDS[id]
  end
  -- Explicit silence for clear-family
  if id == "CLEAR" or id == "SUNNY" or id == "FOG" or id == "MIST" then
    return nil
  end
  if Types.channel(def, "rain") >= 0.5 then
    return { file = "rain_heavy", gain = 0.6 }
  end
  if Types.channel(def, "rain") > 0 then
    return { file = "rain", gain = 0.45 }
  end
  return nil
end
Audio.bedFor = bedFor

-- ------- loading
--
-- Once per file, and never retried after a failure: a missing sound costs
-- one log line and silence, not a stutter every frame.

local cache, failed = {}, {}
local pathTried = {}

-- ENGINE PATH (correct):
--   mod.assets:path("assets/sounds/rain.ogg") → PhysFS path the host can open
--   love.audio.newSource(path, "static"|"stream")
-- ByteData/newSource is unreliable on Gen1Recomp's sandboxed Love build.

local function assetPath(relative)
  if not mod then return nil end
  local p
  if mod.assets and type(mod.assets.path) == "function" then
    local ok, res = pcall(function() return mod.assets:path(relative) end)
    if ok and type(res) == "string" and res ~= "" then return res end
  end
  if type(mod.path) == "string" and mod.path ~= "" then
    return mod.path .. "/" .. relative
  end
  return nil
end

local function candidatePaths(name)
  local rels = {
    Audio.DIR .. name .. ".ogg",
    Audio.DIR .. name .. ".mp3",
    "assets/sounds/" .. name .. ".ogg",
    "assets/sounds/" .. name .. ".mp3",
    "sounds/" .. name .. ".ogg",
    "sounds/" .. name .. ".mp3",
    name .. ".ogg",
    name .. ".mp3",
  }
  local out = {}
  for _, rel in ipairs(rels) do
    local full = assetPath(rel)
    if full then out[#out + 1] = full end
    out[#out + 1] = rel  -- relative fallback for hosts that resolve from mod root
  end
  return out
end

local function makeSourceFromPath(path, kind)
  if not (love and love.audio and love.audio.newSource) then return nil end
  kind = kind or "static"
  local ok, src = pcall(love.audio.newSource, path, kind)
  if ok and src then return src end
  if kind == "stream" then
    ok, src = pcall(love.audio.newSource, path, "static")
    if ok and src then return src end
  end
  return nil
end

local function makeSourceFromBytes(bytes, label, kind)
  if not (love and love.audio and love.audio.newSource) then return nil end
  kind = kind or "static"
  local bd = byteData(bytes, label)
  if not bd then return nil end
  local function try(fn)
    local ok, src = pcall(fn)
    if ok and src then return src end
    return nil
  end
  if love.sound and love.sound.newDecoder then
    local src = try(function()
      return love.audio.newSource(love.sound.newDecoder(bd), kind)
    end)
    if src then return src end
  end
  local src = try(function() return love.audio.newSource(bd, kind) end)
  if src then return src end
  if love.sound and love.sound.newSoundData then
    src = try(function()
      return love.audio.newSource(love.sound.newSoundData(bd))
    end)
    if src then return src end
  end
  return nil
end

local function sourceFor(name, kind)
  -- Beds always use static + unique Source instances so looping is seamless
  -- and two slots never share one Source (shared cache caused gaps/stops).
  kind = "static"
  local key = name .. "/" .. kind
  if not (love and love.audio) then return nil end

  local function finish(src)
    if not src then return nil end
    cache[key] = src  -- template only
    failed[key] = nil
    if src.clone then
      local ok, c = pcall(function() return src:clone() end)
      -- A clone must be a distinct voice. Some constrained/wrapped backends
      -- have returned the same Source object; treating that as a clone lets a
      -- later play restart the sound already in flight.
      if ok and c and c ~= src then return c end
    end
    -- No clone: build a fresh instance from path/bytes below (do not return template)
    return nil
  end

  -- Prefer cached template → clone
  if cache[key] then
    local t = cache[key]
    if t.clone then
      local ok, c = pcall(function() return t:clone() end)
      if ok and c and c ~= t then return c end
    end
  end

  -- 1) Path-based (preferred — matches engine Sound/Music)
  for _, path in ipairs(candidatePaths(name)) do
    local src = makeSourceFromPath(path, kind)
    local inst = finish(src)
    if inst then return inst end
    if src then
      -- clone failed; create a second independent source from path
      local src2 = makeSourceFromPath(path, kind)
      if src2 then return src2 end
      return src
    end
  end

  -- 2) mod:read bytes → Decoder/Source (fallback)
  local data, label
  for _, try in ipairs({ ".ogg", ".mp3" }) do
    for _, prefix in ipairs({ Audio.DIR, "assets/sounds/", "sounds/", "" }) do
      local ok, body = pcall(function() return mod:read(prefix .. name .. try) end)
      if ok and body and type(body) == "string" and #body > 32 then
        data, label = body, name .. try
        break
      end
    end
    if data then break end
  end
  if data then
    local src = makeSourceFromBytes(data, label, kind)
    local inst = finish(src)
    if inst then return inst end
    if src then
      local src2 = makeSourceFromBytes(data, label, kind)
      if src2 then return src2 end
      return src
    end
  end

  if not failed[key] then
    failed[key] = true
    pcall(function()
      mod.log:warn("weather sound %s could not be opened (path+bytes)", name)
    end)
  end
  return nil
end

function Audio.invalidate()
  -- invalidate is a hard engine/resource reset. Do not leave thunder from the
  -- old audio context ringing while the new Sources are created.
  for _, src in ipairs(Audio._oneshots or {}) do
    pcall(function()
      if src.setVolume then src:setVolume(0) end
      if src.stop then src:stop() end
    end)
  end
  for _, src in pairs(cache) do pcall(function() src:stop() end) end
  cache, failed = {}, {}
  Audio.slots = { {}, {} }
  Audio.wind = { level = 0, file = nil }
  Audio._oneshots = {}
  Audio._oneshotMeta = setmetatable({}, { __mode = "k" })
  Audio._pendingStrikeEvents = {}
  Audio._scheduledThunder = {}
  if Lightning and Lightning.clearWorldStrikeBatches then pcall(Lightning.clearWorldStrikeBatches) end
  Audio._audioClock = 0
  Audio._lastThunderAt = -1e9
  Audio._indoorMix = 0
  Audio._indoorState = nil
  Audio._filterState = setmetatable({}, { __mode = "k" })
  Audio._worldAudioWasActive = false
  Audio._frameAudioCfg = nil
end

-- ------- the two bed slots

Audio.slots = { {}, {} }     -- { file, src, level, target }
Audio.wind = { level = 0, file = nil }   -- plays over any bed
Audio.lastStrike = -1

local function slotFor(file)
  for i = 1, 2 do
    if Audio.slots[i].file == file then return Audio.slots[i] end
  end
  return nil
end

local function freeSlot()
  local quietest, best = nil, 2
  for i = 1, 2 do
    local s = Audio.slots[i]
    if not s.file then return s end
    if (s.level or 0) < best then quietest, best = s, s.level or 0 end
  end
  return quietest
end

-- ------- volume
--
-- Two multipliers on top of the bed's own gain, both continuous so
-- nothing steps: how much of the weather is actually falling, and where
-- the player is.

-- True only when the player is in the live overworld (or battle).
-- Title screen, launcher, and pure menus have no mapId / world visibility.
local function inOverworldAudio()
  local now = Scene.now
  if not now then return false end
  -- Title / launcher: Scene has no live map. Overworld always has mapId.
  if now.visible == "battle" then return true end
  if now.mapId then return true end
  return false
end

local function contextGain()
  if not inOverworldAudio() then return 0 end
  local cfg = audioCfg()
  local vis = Scene.now and Scene.now.visible
  if vis == "battle" then
    return tonumber(cfg.battle) or 0.35
  end
  -- Indoor attenuation cross-fades with the same state as the low-pass filter.
  -- Before the first update, seed from the scene so loading a save inside a
  -- building never gets one full-volume outdoor frame.
  if Audio._indoorState == nil then
    Audio._indoorMix = indoorTarget()
  end
  local mix = math.max(0, math.min(1, tonumber(Audio._indoorMix) or 0))
  local inside = tonumber(cfg.indoors) or 0.55
  -- 8.1.52 indoor audibility contract: building entry can reduce the already
  -- distance-adjusted outdoor weather bed by at most 60%. The player can still
  -- fully silence Weather FX with WEATHER SFX=OFF; this floor applies only to
  -- automatic building occlusion. It intentionally clamps legacy config/menu
  -- values below 0.40 so old saves cannot recreate the near-silent behavior.
  local retained = tonumber(Audio.INDOOR_ACOUSTICS.minRetainedGain) or 0.40
  inside = math.max(retained, math.min(1, inside))
  return 1 - (1 - inside) * mix
end

function Audio.masterGain()
  local sfx = Settings.get("sfx")
  if sfx == "off" or sfx == false then return 0 end
  local cfg = audioCfg()
  if cfg.enabled == false then return 0 end
  local named = { low = 0.4, medium = 0.7, high = 1.0, off = 0 }
  local row = named[sfx]
  if row == nil then row = 0.85 end  -- default audible if row missing
  return row * (tonumber(cfg.volume) or 1) * contextGain()
end


-- WeatherState intentionally zeros live channels indoors so precipitation is
-- not DRAWN through roofs. Audio needs different authority: the outside weather
-- is still active and Config.audio.indoors is the attenuation for hearing it
-- through a building. Outdoors use eased live channels; indoors use the static
-- current-weather definition.
function Audio.channelForContext(key)
  local live = 0
  pcall(function() live = tonumber(State.channel(key)) or 0 end)
  if not (Scene.now and Scene.now.indoors) then return live end
  local outside = nil
  pcall(function()
    local cur = State.current and State.current()
    if cur then outside = tonumber(Types.channel(cur, key)) end
  end)
  if outside ~= nil then return math.max(0, outside) end
  return live
end

-- Thunder used to have a hard 45% volume floor. Indoors that defeated the
-- building attenuation entirely (e.g. 0.24 * 0.8 = 0.192 was forced back to
-- 0.45). Keep the outdoor presence floor, but never let it override occlusion.
local function thunderVolume(master, thunderGain)
  local v = math.max(0, tonumber(master) or 0) * math.max(0, tonumber(thunderGain) or 1)
  local mix = math.max(0, math.min(1, tonumber(Audio._indoorMix) or 0))
  if mix <= 0.001 then v = math.max(0.45, v) end
  return math.min(1, v)
end
Audio.thunderVolume = thunderVolume

-- ------- the tick


local function rainFamilyId(id)
  -- Strict rain-family. Never substring-match STORM (would match DUSTSTORM).
  if not id then return false end
  id = tostring(id):upper()
  if id == "DUSTSTORM" or id == "SANDSTORM" or id == "ASHFALL"
      or id == "FLOCKSTORM" or id == "SNOW_LIGHT" or id == "BLIZZARD"
      or id == "HAIL" or id == "CLEAR" or id == "FOG" or id == "MIST" then
    return false
  end
  if id:find("RAIN", 1, true) ~= nil then return true end
  if id == "STORM" or id == "PSYSTORM" or id == "DRAGONSTORM" then return true end
  if id == "SLEET" or id == "GALE" or id == "THUNDERSNOW" or id == "PRIMAL_RAIN"
      or id == "HEAVY_RAIN" then
    return true
  end
  return false
end

local function strikeWeatherId(id)
  -- Audio follows the exact same authored authority as the visual scheduler.
  -- RAIN_LIGHT (RAIN) and RAIN_HEAVY (HEAVY) have no strike channel and must
  -- NEVER thunder, even while an outgoing storm channel is still easing down.
  if not id then return false end
  id = tostring(id):upper()
  if Types.hasLightning then return Types.hasLightning(id) end
  local def = Types.get and Types.get(id) or (State.current and State.current())
  return Types.channel(def, "strike") > 0.01
end
Audio.strikeWeatherId = strikeWeatherId

local function stopSource(src)
  if not src then return end
  pcall(function()
    if src.setVolume then src:setVolume(0) end
    if src.setLooping then src:setLooping(false) end
    if src.stop then src:stop() end
  end)
end

local function oneShotAlive(src)
  if not src then return false end
  if type(src.isPlaying) == "function" then
    local ok, playing = pcall(function() return src:isPlaying() end)
    if ok then return playing == true end
  end
  -- Standard Love Sources expose isPlaying(), but if a wrapped host does not,
  -- expire known thunder files by their real sample duration. This prevents a
  -- six-voice pool from becoming permanently full just because playback state
  -- cannot be queried. The small margins are intentionally longer than the
  -- shipped files, so this never clips a real sample early.
  local meta = Audio._oneshotMeta and Audio._oneshotMeta[src]
  if meta then
    local duration = Audio.THUNDER_DURATION and Audio.THUNDER_DURATION[meta.name]
    local started = tonumber(meta.startedAt)
    if duration and started then
      local pitch = math.max(0.25, tonumber(meta.pitch) or 1)
      return ((tonumber(Audio._audioClock) or 0) - started) < (duration / pitch)
    end
  end
  return true
end

local function pruneOneShots()
  local list = Audio._oneshots or {}
  Audio._oneshotMeta = Audio._oneshotMeta or setmetatable({}, { __mode = "k" })
  local w = 0
  for r = 1, #list do
    local src = list[r]
    if oneShotAlive(src) then
      w = w + 1
      if w ~= r then list[w] = src end
    else
      Audio._oneshotMeta[src] = nil
    end
  end
  for i = #list, w + 1, -1 do list[i] = nil end
  Audio._oneshots = list
  return list
end
Audio.pruneOneShots = pruneOneShots

local function thunderVoiceCounts()
  local total, rolls = 0, 0
  for _, src in ipairs(pruneOneShots()) do
    total = total + 1
    local meta = Audio._oneshotMeta and Audio._oneshotMeta[src]
    if meta and meta.name == "thunder_roll" then rolls = rolls + 1 end
  end
  return total, rolls
end
Audio.thunderVoiceCounts = thunderVoiceCounts

local function strikeRateNow()
  -- Natural handoffs own a deliberately staged live strike channel; manual
  -- pins have no softTo and therefore retain exact definition authority.
  if State and State.softTo and State.synoptic then
    local tr=State.synoptic()
    if type(tr)=="table" and tr.active then
      return math.max(0,tonumber(State.ch and State.ch.strike) or 0)
    end
  end
  local id = State and State.id
  local rate = 0
  pcall(function()
    if Types.strikeRate then
      rate = Types.strikeRate(id)
    else
      local def = Types.get and Types.get(id) or (State.current and State.current())
      rate = tonumber(Types.channel(def, "strike")) or 0
    end
  end)
  return math.max(0, tonumber(rate) or 0)
end
Audio.strikeRateNow = strikeRateNow

-- Legacy helper kept for external callers/tests. Thunder no longer has a
-- cooldown: each bolt is scheduled independently and its physical distance is
-- what spaces the sounds out.
local function thunderGapForRate(_rate)
  return 0
end
Audio.thunderGapForRate = thunderGapForRate

local function clearThunderQueues()
  Audio._pendingStrikeEvents = {}
  Audio._scheduledThunder = {}
  Audio._psychicBoltCounter = 0
  if Lightning and Lightning.clearWorldStrikeBatches then
    pcall(Lightning.clearWorldStrikeBatches)
  elseif Lightning then
    Lightning.worldStrikeBatches = {}
  end
end
Audio.clearThunderQueues = clearThunderQueues

local function queueStrikeEvent(serial, now, wxId, strikeRate)
  serial = tonumber(serial) or 0
  if serial <= 0 then return false end
  Audio._pendingStrikeEvents = Audio._pendingStrikeEvents or {}
  for _, e in ipairs(Audio._pendingStrikeEvents) do
    if tonumber(e.serial) == serial then return false end
  end
  local legendaryPick = nil
  pcall(function() legendaryPick = Legendary.thunderSound() end)
  Audio._pendingStrikeEvents[#Audio._pendingStrikeEvents + 1] = {
    serial = serial,
    visualAt = tonumber(now) or 0,
    createdAt = tonumber(now) or 0,
    wxId = wxId,
    strikeRate = math.max(0, tonumber(strikeRate) or 0),
    legendaryPick = legendaryPick,
  }
  while #Audio._pendingStrikeEvents > 24 do table.remove(Audio._pendingStrikeEvents, 1) end
  return true
end
Audio.queueStrikeEvent = queueStrikeEvent

local function randomUnit()
  local r = (love and love.math and love.math.random) or math.random
  local ok, v = pcall(r)
  if not ok then return 0.5 end
  return clamp01(tonumber(v) or 0.5)
end

local function rangeRand(a, b)
  a, b = tonumber(a) or 0, tonumber(b) or tonumber(a) or 0
  if b < a then a, b = b, a end
  return a + (b - a) * randomUnit()
end

local function psychicDistanceT(distance)
  local mix = Audio.THUNDER_MIX or {}
  local a = tonumber(mix.psychicFarStart) or 420
  local b = math.max(a + 1, tonumber(mix.psychicFarFull) or 900)
  return smooth01((math.max(0, tonumber(distance) or a) - a) / (b - a))
end
Audio.psychicDistanceT = psychicDistanceT

local function psychicThunderTone(role, distanceGain, distance)
  local mix = Audio.THUNDER_MIX or {}
  local dg = clamp01(distanceGain)
  local farT = psychicDistanceT(distance)
  local lo, hi, gain, highGain
  if role == "crack" then
    lo = tonumber(mix.psychicCrackPitchMin) or 0.84
    hi = tonumber(mix.psychicCrackPitchMax) or 0.93
    gain = tonumber(mix.psychicCrackGain) or 0.88
    highGain = tonumber(mix.psychicCrackHighGain) or 0.40
  elseif role == "rumble" then
    lo = tonumber(mix.psychicRumblePitchMin) or 0.58
    hi = tonumber(mix.psychicRumblePitchMax) or 0.66
    gain = tonumber(mix.psychicRumbleGain) or 0.48
    highGain = tonumber(mix.psychicRumbleHighGain) or 0.12
  elseif role == "farTail" then
    lo = tonumber(mix.psychicFarTailPitchMin) or 0.40
    hi = tonumber(mix.psychicFarTailPitchMax) or 0.53
    gain = tonumber(mix.psychicFarTailGain) or 0.52
    highGain = tonumber(mix.psychicFarTailHighGain) or 0.035
  elseif role == "farBoom" then
    lo = tonumber(mix.psychicFarBoomPitchMin) or 0.50
    hi = tonumber(mix.psychicFarBoomPitchMax) or 0.64
    gain = tonumber(mix.psychicFarBoomGain) or 0.78
    highGain = tonumber(mix.psychicFarBoomHighGain) or 0.055
  else
    lo = tonumber(mix.psychicBoomPitchMin) or 0.68
    hi = tonumber(mix.psychicBoomPitchMax) or 0.79
    gain = tonumber(mix.psychicBoomGain) or 0.68
    highGain = tonumber(mix.psychicBoomHighGain) or 0.22
  end

  -- Medium distance progressively lowers pitch and removes transient energy
  -- before the hard role transition reaches a fully distant boom.
  if role == "crack" or role == "boom" then
    local pitchDrop = (role == "crack") and 0.16 or 0.10
    lo, hi = lo - farT * pitchDrop, hi - farT * pitchDrop
    highGain = highGain * (1 - farT * 0.72)
  end
  -- Distance volume remains handled independently. This only shapes spectrum;
  -- far thunder is quieter overall but has more low-frequency weight.
  highGain = math.max(0.025, math.min(1, highGain * (0.64 + 0.36 * dg)))
  return rangeRand(lo, hi), math.max(0, gain), highGain
end
Audio.psychicThunderTone = psychicThunderTone

local function scheduleBoltThunder(event, distances)
  Audio._scheduledThunder = Audio._scheduledThunder or {}
  local count = #distances
  local mix = Audio.THUNDER_MIX or {}
  local wxId = tostring(event and event.wxId or ""):upper()
  local psychic = wxId == "PSYSTORM"

  -- PSYSTORM can emit several visible bolts in one burst. Playing thunder for
  -- every one produced too many overlapping voices, especially when distant
  -- bolts also own a low rolling tail. Keep the spatial/distance mix intact,
  -- but only every SECOND actual psychic bolt is acoustically active. The
  -- cadence is continuous across bursts: 1 silent, 2 audible, 3 silent, 4
  -- audible... Ordinary lightning-capable weather remains one sound per bolt.
  local audible = nil
  local audibleCount = count
  if psychic then
    audible = {}
    audibleCount = 0
    local serial = tonumber(Audio._psychicBoltCounter) or 0
    for i = 1, count do
      serial = serial + 1
      if (serial % 2) == 0 then
        audible[i] = true
        audibleCount = audibleCount + 1
      end
    end
    Audio._psychicBoltCounter = serial
  end

  local primaryIndex, primaryDistance = nil, math.huge
  if psychic then
    for i, raw in ipairs(distances) do
      if audible[i] then
        local d = math.max(0, tonumber(raw) or tonumber(mix.fallbackDistance) or 320)
        if d < primaryDistance then primaryDistance, primaryIndex = d, i end
      end
    end
  end
  local visualAt = tonumber(event.visualAt) or tonumber(Audio._audioClock) or 0
  local farStart = tonumber(mix.psychicFarStart) or 420

  for i, distance in ipairs(distances) do
    if (not psychic) or audible[i] then
      distance = math.max(0, tonumber(distance) or tonumber(mix.fallbackDistance) or 320)
      local dg = thunderDistanceGain(distance)
      local dueAt = visualAt + thunderDistanceDelay(distance)
      local role, pitch, eventGain, highGain
      if psychic then
        if distance >= farStart then
          -- A distant strike has no audible rifle-like crack. Its transient has
          -- been absorbed by distance, leaving a broad low thunder arrival.
          role = "farBoom"
        else
          role = (i == primaryIndex) and "crack" or "boom"
        end
        pitch, eventGain, highGain = psychicThunderTone(role, dg, distance)
        if role ~= "crack" then
          dueAt = dueAt + rangeRand(mix.psychicSecondaryStaggerMin or 0.035,
                                    mix.psychicSecondaryStaggerMax or 0.105)
        end
      end
      Audio._scheduledThunder[#Audio._scheduledThunder + 1] = {
        serial = event.serial, wxId = event.wxId, strikeRate = event.strikeRate,
        legendaryPick = event.legendaryPick, burstSize = count, audibleBurstSize = audibleCount, boltIndex = i,
        distance = distance, distanceGain = dg, visualAt = visualAt, dueAt = dueAt,
        psychicRole = role, pitch = pitch, eventGain = eventGain,
        toneHighGain = highGain,
      }

      -- Only an AUDIBLE distant psychic bolt receives a later low-frequency
      -- body. A skipped bolt must consume zero thunder voices.
      if psychic and distance >= farStart then
        local tailPitch, tailGain, tailHigh = psychicThunderTone("farTail", dg, distance)
        Audio._scheduledThunder[#Audio._scheduledThunder + 1] = {
          serial = event.serial, wxId = event.wxId, strikeRate = event.strikeRate,
          legendaryPick = event.legendaryPick, burstSize = count, audibleBurstSize = audibleCount, boltIndex = i,
          distance = distance, distanceGain = dg, visualAt = visualAt,
          dueAt = visualAt + thunderDistanceDelay(distance)
              + rangeRand(mix.psychicFarTailDelayMin or 0.26, mix.psychicFarTailDelayMax or 0.62),
          psychicRole = "farTail", pitch = tailPitch, eventGain = tailGain,
          toneHighGain = tailHigh, isRumbleLayer = true,
        }
      end
    end
  end

  -- Close/medium audible bursts still get one shared storm body. Silent bolts
  -- do not create or influence this layer.
  if psychic and audibleCount > 0 and primaryIndex and primaryDistance < farStart then
    local dg = thunderDistanceGain(primaryDistance)
    local pitch, eventGain, highGain = psychicThunderTone("rumble", dg, primaryDistance)
    Audio._scheduledThunder[#Audio._scheduledThunder + 1] = {
      serial = event.serial, wxId = event.wxId, strikeRate = event.strikeRate,
      legendaryPick = event.legendaryPick, burstSize = count, audibleBurstSize = audibleCount, boltIndex = primaryIndex,
      distance = primaryDistance, distanceGain = dg, visualAt = visualAt,
      dueAt = visualAt + thunderDistanceDelay(primaryDistance)
          + rangeRand(mix.psychicRumbleDelayMin or 0.16, mix.psychicRumbleDelayMax or 0.28),
      psychicRole = "rumble", pitch = pitch, eventGain = eventGain,
      toneHighGain = highGain, isRumbleLayer = true,
    }
  end

  table.sort(Audio._scheduledThunder, function(a, b)
    return (tonumber(a.dueAt) or 0) < (tonumber(b.dueAt) or 0)
  end)
end
Audio.scheduleBoltThunder = scheduleBoltThunder

local fallbackDistanceOne = { 320 }
local function resolveStrikeEvents(now)
  local pending = Audio._pendingStrikeEvents or {}
  local hasWorldDistanceBridge = Lightning and type(Lightning.takeWorldStrikeBatch) == "function"
  local grace = hasWorldDistanceBridge
      and math.max(0, tonumber((Audio.THUNDER_MIX or {}).fallbackGrace) or 0.12)
      or 0
  local w = 0
  for r = 1, #pending do
    local event = pending[r]
    local batch = nil
    if hasWorldDistanceBridge then
      local ok, got = pcall(Lightning.takeWorldStrikeBatch, event.serial)
      if ok then batch = got end
    end
    if batch and type(batch.distances) == "table" and #batch.distances > 0 then
      scheduleBoltThunder(event, batch.distances)
    elseif (tonumber(now) or 0) - (tonumber(event.createdAt) or 0) >= grace then
      fallbackDistanceOne[1] = tonumber((Audio.THUNDER_MIX or {}).fallbackDistance) or 320
      scheduleBoltThunder(event, fallbackDistanceOne)
    else
      w = w + 1
      if w ~= r then pending[w] = event end
    end
  end
  for i = #pending, w + 1, -1 do pending[i] = nil end
  Audio._pendingStrikeEvents = pending
end
Audio.resolveStrikeEvents = resolveStrikeEvents

local function stopSlot(slot)
  if not slot then return end
  stopSource(slot.src)
  slot.file, slot.src, slot.level, slot._lastVolume, slot._lastPitch, slot._playCheck = nil, nil, 0, nil, nil, 0
end

-- Stop the looping beds and wind, but LEAVE ONE-SHOTS ALONE.
--
-- A thunder clap is fired by a strike and lasts a second or two on its own. It
-- is not part of the bed and must not be cancelled when the bed stops -- doing
-- so cuts a clap off mid-sound, and if the bed-stop runs every frame (as it did
-- for snow-only storms) no clap is ever audible at all.
function Audio.stopBedsOnly()
  for i = 1, 2 do stopSlot(Audio.slots[i]) end
  local w = Audio.wind
  if w then
    stopSource(w.src)
    w.src, w.file, w.level = nil, nil, 0
  end
  Audio._bedFile = nil
end

-- Full stop, one-shots included. For leaving the world entirely -- a save
-- load, the title screen -- where a clap left ringing would be wrong.
function Audio.stopAllBeds()
  Audio.stopBedsOnly()
  if Audio._oneshots then
    for _, src in ipairs(Audio._oneshots) do stopSource(src) end
    Audio._oneshots = {}
  end
  Audio._oneshotMeta = setmetatable({}, { __mode = "k" })
  clearThunderQueues()
end

local function pickThunderForEvent(event, rollVoices)
  local pick = event and event.legendaryPick or nil
  if type(pick) ~= "string" or pick == "" then
    local dryThunder = false
    pcall(function()
      local def = Types.get and Types.get(event and event.wxId)
      if not def then def = State.current and State.current() end
      if def then dryThunder = (tonumber(Types.channel(def, "rain")) or 0) <= 0.02 end
    end)
    local dense = (tonumber(event and event.strikeRate) or 0) >= (tonumber((Audio.THUNDER_MIX or {}).denseRate) or 16)
    local burst = (tonumber(event and event.burstSize) or 1) > 1
    local names = (dryThunder or dense or burst) and Audio.THUNDER_DRY or Audio.THUNDER
    local r = (love.math and love.math.random or math.random)
    pick = names[r(#names)]
  end
  if pick == "thunder_roll" then
    local maxRolls = math.max(0, math.floor(tonumber((Audio.THUNDER_MIX or {}).maxRolls) or 1))
    if rollVoices >= maxRolls then pick = "thunder_clap" end
  end
  return pick
end

local function applyThunderToneFilter(src, indoorMix, highCap)
  if not highCap then return applyIndoorFilter(src, "thunder", indoorMix) end
  if not src or type(src.setFilter) ~= "function" then return false end
  local high = math.min(indoorHighGain("thunder", indoorMix), clamp01(highCap))
  if high >= 0.999 then return applyIndoorFilter(src, "thunder", indoorMix) end
  local ok, supported = pcall(function()
    return src:setFilter({ type = "lowpass", volume = 1.0, highgain = high })
  end)
  if not ok or supported == false then return false end
  Audio._filterState[src] = { kind = "thunder", high = high }
  return true
end
Audio.applyThunderToneFilter = applyThunderToneFilter

local function playThunderEvent(event, master, indoorMix)
  local totalVoices, rollVoices = thunderVoiceCounts()
  local maxVoices = math.max(1, math.floor(tonumber((Audio.THUNDER_MIX or {}).maxVoices) or 48))
  if totalVoices >= maxVoices then
    -- Extremely defensive ceiling only. Normal worst-case PSYSTORM concurrency
    -- is well below 48, so ordinary gameplay still gives every bolt a voice.
    return false
  end

  local pick = pickThunderForEvent(event, rollVoices)
  local src = sourceFor(pick, "static")
  if not src and pick ~= "thunder_clap" then
    pick = "thunder_clap"
    src = sourceFor(pick, "static")
  end
  if not src then
    pcall(function() mod.log:warn("weather thunder sound failed to load (clap/roll/zapdos)") end)
    return false
  end

  local tg = 1
  pcall(function() tg = tonumber(audioCfg().thunderGain) or 1 end)
  local distanceGain = math.max(0, math.min(1, tonumber(event and event.distanceGain) or 1))
  local eventGain = math.max(0, tonumber(event and event.eventGain) or 1)
  local userThunder=Settings.thunderVolumeScale and Settings.thunderVolumeScale() or 1
  local vol = math.min(1, thunderVolume(master, tg) * userThunder * distanceGain * eventGain * acousticGain("thunder"))
  local pitch = tonumber(event and event.pitch)
  local okPlay = pcall(function()
    applyThunderToneFilter(src, indoorMix, event and event.toneHighGain)
    src:setVolume(vol)
    if pitch and src.setPitch then src:setPitch(math.max(0.25, math.min(2.0, pitch))) end
    if src.setLooping then src:setLooping(false) end
    src:play()
  end)
  if not okPlay then return false end

  local now = tonumber(Audio._audioClock) or 0
  Audio._oneshots = Audio._oneshots or {}
  Audio._oneshotMeta = Audio._oneshotMeta or setmetatable({}, { __mode = "k" })
  Audio._oneshots[#Audio._oneshots + 1] = src
  Audio._oneshotMeta[src] = {
    name = pick,
    startedAt = now,
    serial = event and event.serial,
    boltIndex = event and event.boltIndex,
    burstSize = event and event.burstSize,
    distance = event and event.distance,
    distanceGain = distanceGain,
    eventGain = eventGain,
    pitch = pitch,
    psychicRole = event and event.psychicRole,
    toneHighGain = event and event.toneHighGain,
    isRumbleLayer = event and event.isRumbleLayer or false,
    propagationDelay = event and ((tonumber(event.dueAt) or now) - (tonumber(event.visualAt) or tonumber(event.dueAt) or now)) or 0,
  }
  Audio._lastThunderAt = now
  return true
end
Audio.playThunderEvent = playThunderEvent

local function processScheduledThunder(now, master, indoorMix, canThunder)
  resolveStrikeEvents(now)
  local list = Audio._scheduledThunder or {}
  local w = 0
  for r = 1, #list do
    local event = list[r]
    if (tonumber(event.dueAt) or 0) <= now then
      if canThunder then playThunderEvent(event, master, indoorMix) end
    else
      w = w + 1
      if w ~= r then list[w] = event end
    end
  end
  for i = #list, w + 1, -1 do list[i] = nil end
  Audio._scheduledThunder = list
end
Audio.processScheduledThunder = processScheduledThunder

function Audio.update(dt)
  if not (love and love.audio) then return end
  dt = tonumber(dt) or 0
  if dt <= 0 then return end
  if dt > 0.25 then dt = 0.25 end

  -- TITLE/HOME-SCREEN NON-INTERFERENCE.
  --
  -- Weather FX owns only the Sources it created. Older builds called
  -- stopAllBeds() on *every title-screen frame*. Even though that function
  -- targets Weather FX Sources, repeatedly mutating/stopping Sources while the
  -- engine is starting its own title cry can disturb shared/quirky backends.
  -- Clean up exactly once when leaving a live world, then do absolutely no
  -- audio work until a map/battle exists again. A cold boot on the title screen
  -- therefore never touches love.audio Sources at all.
  local worldAudio = inOverworldAudio()
  if not worldAudio then
    if Audio._worldAudioWasActive then
      Audio.stopAllBeds()
    end
    Audio._worldAudioWasActive = false
    Audio._wxId = nil
    Audio._bedFile = nil
    Audio._frameAudioCfg = nil
    return
  end
  Audio._worldAudioWasActive = true

  -- WEATHER=OFF is a hard audio boundary, distinct from AUTO. Stop loops,
  -- ringing thunder and queued strike arrivals once on the transition, then do
  -- no weather-audio work until the ladder is re-enabled.
  local liveWeatherLevel=tonumber(State.level)
  local hardWeatherOff = (liveWeatherLevel~=nil and liveWeatherLevel<=0)
      or (Settings.weatherDisabled and Settings.weatherDisabled())
  if hardWeatherOff then
    if not Audio._hardWeatherOff then
      Audio.stopAllBeds()
      if Lightning and Lightning.reset then pcall(Lightning.reset) end
      Audio._wxId,Audio._bedFile,Audio._frameAudioCfg=nil,nil,nil
    end
    Audio._hardWeatherOff=true
    return
  end
  Audio._hardWeatherOff=false

  local rootCfg=Config.get(); Audio._frameAudioCfg=(rootCfg and rootCfg.audio) or {}
  Audio._audioClock = (tonumber(Audio._audioClock) or 0) + dt
  local indoorMix = stepIndoorMix(dt)

  local master = Audio.masterGain()
  -- One authoritative weather snapshot per audio frame. The old path called
  -- State.current() repeatedly through bed/rain/thunder/wind branches.
  local current = State.current and State.current() or nil
  local wxId = State.id or (current and current.id) or nil
  if type(wxId) == "string" then wxId = wxId:upper() end


  local targetWxId = State.softTo and tostring(State.softTo):upper() or nil
  local syn = nil
  if targetWxId and State.synoptic then
    local v=State.synoptic()
    if type(v)=="table" and v.active then syn=v end
  end

  -- Bed identity follows the source/target WEATHER family, while gain follows
  -- the continuous precipitation channels below. This lets rain audio emerge
  -- with the first real drops during a natural onset instead of staying silent
  -- until State.id commits. Manual selections still snap State.id immediately.
  local wantFile, wantGain = nil, 0
  -- Continuous rain bed: rain-family weather with an audible precipitation context.
  -- Multi-layer 60s seamless beds remove audible loop pauses.
  local rainCh = Audio.channelForContext("rain")
  local snowCh = Audio.channelForContext("snow")
  -- The same snow-only blind spot as nudgeFromVisual above. rainFamilyId()
  -- answers true for THUNDERSNOW -- correctly, it wants the `storm` bed -- but
  -- this gate also demanded a RAIN channel, and THUNDERSNOW has none. So the
  -- bed span up and was cut a frame later, which is the second half of "the
  -- sound stops after a few seconds".
  --
  -- The question is whether precipitation is falling, not whether RAIN is. Rain
  -- still drives density and gain when it is the one present, so rain weathers
  -- are unchanged.
  local precipCh = rainCh
  if snowCh > precipCh then precipCh = snowCh end

  -- A finite storm front owns its rain bed by PHYSICAL distance, not by the
  -- player's locally eased precipitation channel. Crossing the rain footprint
  -- therefore does not revoke audio: the bed remains at authored full gain
  -- throughout the footprint, then falls off smoothly from its physical edge.
  -- `present` intentionally remains true a little beyond audible range so the
  -- local eased channel cannot briefly reassert a full-volume bed behind a
  -- receding front.
  local frontRain=nil
  do
    local DW=distantWeather()
    if DW and DW.rainAudio then
      local ok,q=pcall(DW.rainAudio)
      if ok and type(q)=="table" and q.present and q.weather then frontRain=q end
    end
  end
  local frontGain=frontRain and math.max(0,math.min(1,tonumber(frontRain.gain) or 0)) or 0
  local frontWxId=frontRain and tostring(frontRain.weather):upper() or nil
  local frontOwnsRain=frontWxId and rainFamilyId(frontWxId) or false

  local precipAudible = precipCh > 0.02
  local bedWxId, bedDef = wxId, current
  if frontOwnsRain then
    bedWxId=frontWxId
    bedDef=Types.get and Types.get(frontWxId) or nil
    precipAudible=frontGain>0.002
  end
  if (not frontOwnsRain) and syn and targetWxId then
    local targetDef = Types.get and Types.get(targetWxId) or nil
    local sourceRain = rainFamilyId(wxId)
    local targetRain = rainFamilyId(targetWxId)
    if sourceRain and targetRain then
      -- Existing rain/storm audio changes character around the middle of the
      -- precipitation handoff instead of at the final id commit.
      if (tonumber(syn.precipU) or 0) >= 0.50 then bedWxId,bedDef=targetWxId,targetDef end
    elseif targetRain and precipAudible then
      bedWxId,bedDef=targetWxId,targetDef
    elseif sourceRain then
      bedWxId,bedDef=wxId,current
    end
  end
  local allowRainSfx = master > 0 and rainFamilyId(bedWxId) and precipAudible
  -- A weather listed as `false` in BEDS is deliberately silent and must not be
  -- given the generic rain bed by the fallback below -- that fallback exists so
  -- an UNLISTED rain type still gets rain, not to override an explicit choice.
  local silentBed = bedDef and bedDef.id and Audio.BEDS[bedDef.id] == false or false
  -- THE FALLBACK MUST NOT INVENT RAIN.
  --
  -- Every bed in assets/sounds is a RAIN recording. The fallback below exists
  -- so an UNLISTED rain type still gets rain -- it was never meant to give a
  -- rain bed to a weather with no rain in it.
  --
  -- The `silentBed` check above matches State.current().id against BEDS, which
  -- only works for the base weather. A weather VARIANT has its own id, is not
  -- in BEDS, and so slipped past it: bedFor() returned nil (the def has no rain
  -- channel), the fallback then handed it the generic rain bed, and
  -- THUNDERSNOW sounded like rain again a minute in -- once a variant became
  -- active.
  --
  -- Matching ids cannot cover weathers this table has never heard of. Ask the
  -- weather instead: no rain channel, no rain bed. That holds for THUNDERSNOW,
  -- for its variants, and for anything added later.
  -- RAIN THE WEATHER HAS, NOT RAIN THE CHANNEL CURRENTLY SHOWS.
  --
  -- `State.channel("rain")` is the LIVE value: eased between weathers and
  -- pushed around by the drifting front system. For a snow-only weather it
  -- starts at 0 and can creep above the threshold later as a neighbouring
  -- front bleeds in -- which is why THUNDERSNOW was silent at first and started
  -- sounding like rain roughly a minute in. The gate was reading a number that
  -- legitimately changes, so it legitimately unlocked.
  --
  -- The bed should follow what the WEATHER is, and THUNDERSNOW is snow-only for
  -- its whole duration. Read the definition's own rain channel, which is
  -- static, and fall back to the live value only when there is no definition to
  -- ask.
  local defRain = bedDef and tonumber(Types.channel(bedDef, "rain")) or nil
  local hasRainChannel
  if defRain ~= nil then
    hasRainChannel = defRain > 0.02
  else
    hasRainChannel = rainCh > 0.02
  end
  if allowRainSfx and not silentBed and (hasRainChannel or bedFor(bedDef)) then
    local bed = bedFor(bedDef)
    if (not bed or not bed.file) and hasRainChannel then
      bed = { file = "rain", gain = 0.55 }
    end
    if bed and bed.file then
      wantFile = bed.file
      if frontOwnsRain then
        -- Distance is the only spatial attenuation for a front rain bed. At or
        -- inside the physical precipitation edge frontGain is 1.0, so the bed
        -- reaches exactly its authored full weather gain. Only after exiting
        -- can the target begin to decrease.
        wantGain = (bed.gain or 0.6) * frontGain
      else
        local dens = math.max(0.35, precipCh)
        wantGain = (bed.gain or 0.6) * 0.8 * math.min(1.2, 0.5 + dens * 0.65)
      end
    end
  else
    -- Weather changed away from rain, or no audible precipitation context: stop.
    wantFile, wantGain = nil, 0
  end

  local weatherChanged = wxId ~= Audio._wxId
  if weatherChanged or wantFile ~= Audio._bedFile then
    Audio._wxId = wxId
    Audio._bedFile = wantFile
    for i = 1, 2 do
      local slot = Audio.slots[i]
      if slot and (not wantFile or slot.file ~= wantFile) then
        stopSlot(slot)
      end
    end
    if not wantFile then
      Audio.stopAllBeds()
      -- Leaving rain family: stop lingering thunder
      if Audio._oneshots then
        for _, src in ipairs(Audio._oneshots) do stopSource(src) end
        Audio._oneshots = {}
      end
    end
    -- A transition BETWEEN lightning weathers may keep a clap already in
    -- flight. A transition INTO a non-lightning weather must not: RAIN and
    -- HEAVY are rain-only from the first frame selected.
    if weatherChanged and not strikeWeatherId(wxId) then
      for _, src in ipairs(Audio._oneshots or {}) do stopSource(src) end
      Audio._oneshots = {}
      Audio._oneshotMeta = setmetatable({}, { __mode = "k" })
      Audio._lastStrikeSerial = tonumber(Lightning.strikeSerial) or Audio._lastStrikeSerial or 0
      Lightning.justStruck = false
    end
    -- Bed file swap between lightning-capable storms must NOT cut thunder mid-clap.
  end

  if not allowRainSfx then
    for i = 1, 2 do
      local slot = Audio.slots[i]
      if slot and slot.file then stopSlot(slot) end
    end
    Audio._bedFile = nil
    -- Do NOT stop thunder oneshots here — they are independent of rain beds.
  end

  if wantFile and not slotFor(wantFile) then
    local slot = freeSlot()
    if slot then
      slot.file, slot.level = wantFile, 0
      slot.src = sourceFor(wantFile, "static")
      if slot.src then
        pcall(function()
          slot.src:setLooping(true)
          slot.src:setVolume(0)
          slot.src:play()
        end)
      else
        slot.file = nil
      end
    end
  end

  local seconds = 0.25
  for i = 1, 2 do
    local slot = Audio.slots[i]
    if slot and slot.file then
      if slot.file ~= wantFile then
        stopSlot(slot)
      else
        local target = wantGain
        local step = dt / seconds
        if slot.level < target then
          slot.level = math.min(target, slot.level + step)
        elseif slot.level > target then
          slot.level = math.max(target, slot.level - step)
        end
        if slot.src then
          pcall(function()
            local vol = math.min(1, (slot.level or 0) * master * acousticGain("rain"))
            applyIndoorFilter(slot.src, "rain", indoorMix)
            setVolumeIfChanged(slot.src,slot,vol)
            -- OpenAL/Love playback-state queries cross the Lua/native boundary.
            -- Poll at 10 Hz instead of every rendered frame; looping is set once
            -- when the source is created and never depends on game pause state.
            slot._playCheck=(slot._playCheck or 0)+dt
            if target > 0 and vol > 0.01 and slot._playCheck>=.10 then
              slot._playCheck=slot._playCheck-.10
              local playing = true
              if slot.src.isPlaying then playing = slot.src:isPlaying() end
              if not playing then
                if slot.src.seek then pcall(function() slot.src:seek(0) end) end
                slot.src:play()
              end
            end
          end)
        end
        if target <= 0 then stopSlot(slot) end
      end
    end
  end

  -- ------- wind
  do
    local want, wFile = 0, nil
    local windOk = master > 0
    local windCfg = audioCfg()
    if windCfg and windCfg.wind == false then windOk = false end
    local windActive, windPitch = false, 1.0
    if windOk then
      local gust = Audio.channelForContext("gust")
      if gust > 0.05 then
        windActive = true
        local procedural, p = 1.0, 1.0
        local WE = windEngine()
        if WE then
          local ws = WE.peek and WE.peek() or (WE.state and WE.state())
          if ws then
            procedural = math.max(0, math.min(1, tonumber(ws.audio) or 0))
            p = tonumber(ws.pitch) or 1
          end
        end
        -- The sound breathes with the same gust/lull envelope as particles.
        -- A light breeze can nearly disappear; severe weather retains a bed.
        want = math.min(1, gust) * procedural * Audio.WIND.gain * 1.18
        windPitch = math.max(0.82, math.min(1.08, p))
        local windDef=current
        if syn and targetWxId and (tonumber(syn.windU) or 0) > 0.35 and Types.get then
          windDef=Types.get(targetWxId) or current
        end
        wFile = Audio.windFileFor(windDef)
      end
    end
    local w = Audio.wind
    if not windActive then
      if w and w.src then
        stopSource(w.src)
        w.src, w.file, w.level = nil, nil, 0
      end
    else
      if w.src and w.file and wFile and w.file ~= wFile then
        stopSource(w.src)
        w.src, w.file, w.level = nil, nil, 0
      end
      if (not w.src) and wFile then
        w.file = wFile
        w.src = sourceFor(wFile, "static")
        if w.src then
          pcall(function()
            w.src:setLooping(true)
            w.src:setVolume(0)
            w.src:play()
          end)
          w.level = 0
        end
      end
      local step = dt / 0.35
      if (w.level or 0) < want then w.level = math.min(want, (w.level or 0) + step)
      elseif (w.level or 0) > want then w.level = math.max(want, (w.level or 0) - step) end
      if w.src then
        pcall(function()
          applyIndoorFilter(w.src, "wind", indoorMix)
          setPitchIfChanged(w.src,w,windPitch)
          setVolumeIfChanged(w.src,w,math.min(1, (w.level or 0) * master * acousticGain("wind")))
        end)
      end
    end
  end

  -- ------- one delayed thunder event per visible lightning bolt
  local age = Lightning.age or -1
  local thunderOn = true
  local a = audioCfg()
  if a and a.thunder == false then thunderOn = false end
  -- Settings.get() is already guarded and frame-cached. Avoid a second pcall in
  -- this hot audio path; option changes invalidate the cached key immediately.
  local lightMode = tostring(Settings.get("lightning") or "full"):lower()
  if lightMode == "off" then thunderOn = false end

  local thunderWxId = wxId
  local weatherCanThunder = strikeWeatherId(wxId)
  if syn and targetWxId then
    local liveStrike=tonumber(State.ch and State.ch.strike) or 0
    local sourceHas=strikeWeatherId(wxId)
    local targetHas=strikeWeatherId(targetWxId)
    weatherCanThunder = liveStrike > 0.01 and (sourceHas or targetHas)
    if targetHas and (tonumber(syn.stormU) or 0) > 0.02 then thunderWxId=targetWxId
    elseif sourceHas then thunderWxId=wxId
    else thunderWxId=targetWxId end
  end
  local canThunder = thunderOn and master > 0 and weatherCanThunder
  local serial = tonumber(Lightning.strikeSerial) or 0
  local lastSerial = tonumber(Audio._lastStrikeSerial) or 0
  local newStrike = serial > lastSerial
  if not newStrike and Lightning.justStruck == true then
    -- Legacy/tests may only raise justStruck. Give that event a synthetic
    -- monotonic serial so it still enters the same queue.
    serial = lastSerial + 1
    newStrike = true
  end
  if newStrike then
    Audio._lastStrikeSerial = serial
    Lightning.justStruck = false
    if canThunder then
      queueStrikeEvent(serial, tonumber(Audio._audioClock) or 0, thunderWxId, strikeRateNow())
    end
  end

  -- Distant StormCells own their electrical charge independently of the local
  -- weather. A clear map can therefore hear a storm several maps away. These
  -- events use the exact same speed-of-sound delay, attenuation and indoor
  -- filtering as local world bolts, but never create a duplicate local strike.
  if thunderOn and master>0 then
    local DW=distantWeather();local events=DW and DW.takeThunderEvents and DW.takeThunderEvents() or nil
    if events then
      local one=Audio._remoteDistanceOne or {0};Audio._remoteDistanceOne=one
      for i=1,#events do
        local e=events[i];e.visualAt=tonumber(Audio._audioClock) or 0
        one[1]=math.max(0,tonumber(e.distance) or 0)
        scheduleBoltThunder(e,one)
      end
    end
  end

  -- WorldLightning publishes the real distance of every bolt during the render
  -- pass. On the following update those distances resolve the scheduler event
  -- into individual arrivals. No cooldown is applied: two bolts mean two
  -- independent thunder voices, even while the first sound is still ringing.
  processScheduledThunder(tonumber(Audio._audioClock) or 0, master, indoorMix, canThunder)

  -- Existing thunder can still be ringing while the player crosses a doorway.
  -- Re-apply the current occlusion mix so the transition affects the whole sound,
  -- not only one-shots that started after entering/leaving the building.
  for _, src in ipairs(pruneOneShots()) do
    applyIndoorFilter(src, "thunder", indoorMix)
    local tg = 1
    pcall(function() tg = tonumber(audioCfg().thunderGain) or 1 end)
    pcall(function()
      local meta = Audio._oneshotMeta and Audio._oneshotMeta[src]
      local dg = meta and tonumber(meta.distanceGain) or 1
      local userThunder=Settings.thunderVolumeScale and Settings.thunderVolumeScale() or 1
      setVolumeIfChanged(src,meta,math.min(1, thunderVolume(master, tg) * userThunder * math.max(0, dg) * acousticGain("thunder")))
    end)
  end

  Audio.lastStrike = age

end

-- Force a bed to be audible this frame (used when rain/storm is drawn).
function Audio.nudgeFromVisual(weatherId, hasPrecipAnim, hasLightning)
  -- Visual rendering is NOT audio authority. This callback executes from the
  -- draw path after Audio.update(); allowing it to stop a bed makes sound depend
  -- on whether a 2D/3D frame happened to draw precipitation that frame, which is
  -- exactly how audio became audible only while gameplay was paused. Keep this
  -- as diagnostics only. Audio.update follows WeatherState + Scene every frame.
  Audio._lastVisualNudgeId=weatherId
  Audio._lastVisualPrecip=hasPrecipAnim==true
  Audio._lastVisualLightning=hasLightning==true
  return true
end


function Audio.describe()
  local playing = {}
  for i = 1, 2 do
    local s = Audio.slots[i]
    if s.file and (s.level or 0) > 0.01 then
      playing[#playing + 1] = ("%s%.0f%%"):format(s.file, s.level * 100)
    end
  end
  if (Audio.wind.level or 0) > 0.01 then
    playing[#playing + 1] = ("%s%.0f%%"):format(
      Audio.wind.file or "wind", Audio.wind.level * 100)
  end
  if #playing == 0 then return "-" end
  return table.concat(playing, "+")
end

return Audio
