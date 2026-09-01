-- Playback front-end for the MP2K engine: the Gen 3 counterpart of
-- ChipAudio. Same shape -- a QueueableSource fed with rendered buffers --
-- but rendered on the main thread rather than in chip_worker, because
-- Mp2kSynth runs about ten times faster than realtime and a frame only
-- needs ~740 samples. The buffers are correspondingly smaller so the
-- initial fill cannot hitch a frame.
--
-- Sound effects, fanfares and cries are not a separate sound system in
-- Ruby: they are ordinary songs in the same table, distinguished only by
-- which of the four music players they run on. So this holds one
-- independent voice per role, each with its own engine and source, and a
-- fanfare simply mutes the music underneath it while it runs.
local Mp2kSynth = require("src.core.Mp2kSynth")

local Mp2kAudio = {}

local SAMPLE_RATE = Mp2kSynth.SAMPLE_RATE
local BUFFER_SAMPLES = Mp2kSynth.MUSIC_BUFFER_SAMPLES
local BUFFER_COUNT = Mp2kSynth.MUSIC_BUFFER_COUNT

local BASE_VOLUME = 0.7

-- Music can afford a deeper prebuffer than an effect, which wants to be
-- heard now and is usually over before the queue would have drained.
local VOICE_SPEC = {
  bgm = { prefill = 6, fill = 2, loop = true, music = true },
  se = { prefill = 3, fill = 2 },
  fanfare = { prefill = 3, fill = 2, ducks = true },
  cry = { prefill = 3, fill = 2 },
}
Mp2kAudio.VOICES = { "bgm", "se", "fanfare", "cry" }
Mp2kAudio.DEFAULT_VOICE = "bgm"

local voices = {}
for name in pairs(VOICE_SPEC) do voices[name] = {} end

local musicScale = 1
local effectScale = 1

local function spec(name) return VOICE_SPEC[name] or VOICE_SPEC.bgm end

local function ducked()
  local v = voices.fanfare
  return v.source ~= nil and v.songId ~= nil
end

local function applyVolume(name)
  local v = voices[name]
  if not v.source then return end
  local s = spec(name)
  local scale = s.music and musicScale or effectScale
  if v.fade then scale = scale * v.fade.level end
  if s.music and ducked() then scale = 0 end
  v.source:setVolume(BASE_VOLUME * scale)
end

local function applyAllVolumes()
  for _, name in ipairs(Mp2kAudio.VOICES) do applyVolume(name) end
end

local function fill(name, count)
  local v = voices[name]
  local source, engine = v.source, v.engine
  if not (source and engine) then return end
  for _ = 1, count do
    if source:getFreeBufferCount() <= 0 then return end
    if engine:finished() then return end
    local ok, sd = pcall(Mp2kSynth.soundData, engine, BUFFER_SAMPLES, 2)
    if not ok or not sd then return end
    pcall(source.queue, source, sd)
  end
end

function Mp2kAudio.stop(name)
  name = name or Mp2kAudio.DEFAULT_VOICE
  local v = voices[name]
  if not v then return end
  if v.source then pcall(v.source.stop, v.source) end
  v.engine, v.source, v.songId, v.fade = nil, nil, nil, nil
  if spec(name).ducks then applyVolume("bgm") end
end

function Mp2kAudio.stopAll()
  for _, name in ipairs(Mp2kAudio.VOICES) do Mp2kAudio.stop(name) end
end

-- `engine` lets a caller supply a song this module cannot look up, which is
-- how cries play: they are assembled at runtime rather than living in the
-- song table.
function Mp2kAudio.playVoice(name, engine, songId)
  name = name or Mp2kAudio.DEFAULT_VOICE
  local v = voices[name]
  if not (v and engine) then return nil end
  Mp2kAudio.stop(name)
  local ok, source = pcall(love.audio.newQueueableSource,
    SAMPLE_RATE, 16, 2, BUFFER_COUNT)
  if not ok or not source then return nil end
  v.engine = engine
  v.source = source
  v.songId = songId or true
  v.fade = nil
  applyVolume(name)
  if spec(name).ducks then applyVolume("bgm") end
  fill(name, spec(name).prefill)
  source:play()
  return source
end

local function startSong(data, songId, name, loop)
  if type(songId) ~= "number" then return nil end
  local engine = Mp2kSynth.newEngine(data, songId, { allowLoops = loop })
  if not engine then return nil end
  return Mp2kAudio.playVoice(name, engine, songId)
end

function Mp2kAudio.playSong(data, songId, loop)
  local v = voices.bgm
  if v.songId == songId and v.source and v.source:isPlaying() then
    return v.source
  end
  return startSong(data, songId, "bgm", loop ~= false)
end

-- Effects never loop: a GOTO at the end of a jingle would otherwise keep it
-- going forever instead of letting the track run out.
function Mp2kAudio.playEffect(data, songId, name)
  return startSong(data, songId, name or "se", false)
end

-- Ramp a voice out over `frames` 60 Hz frames, then stop it. Mirrors the
-- Gen 1/2 Music.fadeOut contract so callers read the same either side.
function Mp2kAudio.fadeOut(frames, name)
  name = name or Mp2kAudio.DEFAULT_VOICE
  local v = voices[name]
  if not (v and v.source) then return end
  v.fade = { level = 1, step = 1 / math.max(1, frames or 30) }
end

local function updateVoice(name)
  local v = voices[name]
  if not v.source then return end
  if v.fade then
    v.fade.level = v.fade.level - v.fade.step
    if v.fade.level <= 0 then
      Mp2kAudio.stop(name)
      return
    end
    applyVolume(name)
  end
  fill(name, spec(name).fill)
  -- A QueueableSource stops on underrun; restart it while buffers remain.
  if not v.source:isPlaying() and v.source:getFreeBufferCount() < BUFFER_COUNT then
    pcall(v.source.play, v.source)
  end
  if v.engine and v.engine:finished()
      and v.source:getFreeBufferCount() >= BUFFER_COUNT then
    Mp2kAudio.stop(name)
  end
end

function Mp2kAudio.update()
  local wasDucked = ducked()
  for _, name in ipairs(Mp2kAudio.VOICES) do updateVoice(name) end
  if wasDucked and not ducked() then applyVolume("bgm") end
end

function Mp2kAudio.setVolumeLevel(level)
  musicScale = math.max(0, math.min(7, tonumber(level) or 7)) / 7
  applyAllVolumes()
end

function Mp2kAudio.setEffectVolumeLevel(level)
  effectScale = math.max(0, math.min(7, tonumber(level) or 7)) / 7
  applyAllVolumes()
end

function Mp2kAudio.currentSong() return voices.bgm.songId end

function Mp2kAudio.voicePlaying(name)
  local v = voices[name or Mp2kAudio.DEFAULT_VOICE]
  return v ~= nil and v.source ~= nil and v.songId ~= nil
end

function Mp2kAudio.isPlaying() return Mp2kAudio.voicePlaying("bgm") end

function Mp2kAudio.invalidate()
  Mp2kAudio.stopAll()
  Mp2kSynth.invalidate()
end

return Mp2kAudio
