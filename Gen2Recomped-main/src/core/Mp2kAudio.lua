-- Playback front-end for the MP2K engine: the Gen 3 counterpart of
-- ChipAudio. Same shape -- a QueueableSource fed with rendered buffers -- and,
-- like ChipAudio, the MUSIC voice streams from a background worker thread
-- (src/core/mp2k_worker.lua) while everything else renders inline.
--
-- Why the music is threaded: synthesis costs ~1.8us per stereo sample, and
-- filling a song's queue from scratch renders most of a second of audio. On
-- the main thread that landed as a hitch inside Game3:enterMap (playMapMusic
-- -> playSong -> the prefill) plus a stutter tail across the frames behind it,
-- on every warp that changed the song. Off-thread a song change costs the main
-- loop a channel push.
--
-- Sound effects, fanfares and cries stay on the main thread: they are short,
-- they want to be heard on the frame they were asked for rather than one
-- later, and they were never the map-change cost. Their queues are shallow
-- (SYNC_BUFFER_COUNT) so the inline fill stays cheap.
--
-- When love.thread is unavailable (the headless test stub) or the worker
-- fails to start, music falls back to the same inline fill as the effects, so
-- behavior is unchanged -- see the `threaded` branch in each entry point.
--
-- Sound effects, fanfares and cries are not a separate sound system in
-- Ruby: they are ordinary songs in the same table, distinguished only by
-- which of the four music players they run on. So this holds one
-- independent voice per role, each with its own engine and source.
-- sound.c PlayFanfareByFanfareNum is m4aMPlayStop on BGM (pause, keep
-- position) then m4aSongNumStart the jingle; Task_Fanfare /
-- WaitFanfare call m4aMPlayContinue. Muting while the worker still ticks
-- would resume the song where it *would* have been.
local Mp2kSynth = require("src.core.Mp2kSynth")

local Mp2kAudio = {}

local SAMPLE_RATE = Mp2kSynth.SAMPLE_RATE
local BUFFER_SAMPLES = Mp2kSynth.MUSIC_BUFFER_SAMPLES
local STREAM_BUFFER_COUNT = Mp2kSynth.MUSIC_BUFFER_COUNT
local STREAM_BUFFER_SAMPLES = Mp2kSynth.STREAM_BUFFER_SAMPLES
local SYNC_BUFFER_COUNT = Mp2kSynth.SYNC_BUFFER_COUNT

local BASE_VOLUME = 0.7

-- `streamed` marks the voice the worker feeds. prefill/fill apply only to a
-- voice rendering inline: prefill is what a start pays up front, fill is what
-- each later frame tops the queue up by. Both are small now -- a deep inline
-- prebuffer is exactly the hitch this module used to have.
local VOICE_SPEC = {
  bgm = { prefill = 2, fill = 2, loop = true, music = true, streamed = true },
  se = { prefill = 2, fill = 2 },
  fanfare = { prefill = 2, fill = 2, ducks = true },
  se3 = { prefill = 2, fill = 2 },
  cry = { prefill = 2, fill = 2 },
}
-- gMPlayInfo_BGM / SE1 / SE2 / SE3, plus separate cry players.
-- Player 2 is the fanfare voice (MUS_HEAL etc.) but PlaySE on player 2
-- must not m4aMPlayStop BGM -- only PlayFanfare does that.
Mp2kAudio.VOICES = { "bgm", "se", "fanfare", "se3", "cry" }
Mp2kAudio.DEFAULT_VOICE = "bgm"
Mp2kAudio.PLAYER_VOICE = { [1] = "se", [2] = "fanfare", [3] = "se3" }

local voices = {}
for name in pairs(VOICE_SPEC) do voices[name] = {} end

local musicScale = 1
local effectScale = 1

local function spec(name) return VOICE_SPEC[name] or VOICE_SPEC.bgm end

-- ---------------------------------------------------------------------------
-- worker management
-- ---------------------------------------------------------------------------

local worker, cmdCh, outCh
local workerReady -- nil = untried, true = running, false = unavailable

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
  if not (love.thread and love.thread.newThread and love.audio) then
    workerReady = false
    return false
  end
  local ok, thread = pcall(love.thread.newThread, "src/core/mp2k_worker.lua")
  if not ok or not thread then
    workerReady = false
    return false
  end
  cmdCh = love.thread.getChannel("mp2kaudio_cmd")
  outCh = love.thread.getChannel("mp2kaudio_out")
  if not pcall(function() thread:start() end) then
    workerReady = false
    return false
  end
  worker = thread
  workerReady = true
  return true
end

-- If the worker dies mid-synth, fall back to the inline path for the rest of
-- the session rather than going silent.
local function workerAlive()
  if not worker then return false end
  local err = worker:getError()
  if err then
    require("src.core.Logger").warn("mp2k audio worker died: %s", tostring(err))
    workerReady = false
    worker = nil
    return false
  end
  return true
end

-- Only what Mp2kSynth needs to re-read the program bytes on its own thread;
-- sent with every play so a hot-reloaded dataset reaches the worker too.
local function slimAudio(data)
  local audio = (data and data.audio) or {}
  -- NX-only: the versioned cache prefix is resolved here, on the main thread,
  -- because the worker runs in a fresh Lua state with no asset overlay
  -- installed (same hand-off ChipAudio makes for chip_worker).
  local programPrefix = audio.programPrefix
  if require("src.core.Platform").isNX() then
    local prefix = require("src.core.GameVersion").cachePrefix()
    if prefix ~= "" then programPrefix = prefix end
  end
  return { blob = audio.blob, base = audio.base, programPrefix = programPrefix }
end

-- test-only: expose slimAudio so the NX prefix hand-off is verifiable
function Mp2kAudio._slimAudioForTest(data)
  return slimAudio(data)
end

-- ---------------------------------------------------------------------------

local function queueDepth(name, threaded)
  if threaded and spec(name).streamed then return STREAM_BUFFER_COUNT end
  return SYNC_BUFFER_COUNT
end

-- m4aMPlayStop / m4aMPlayContinue. Pause the Source and freeze the
-- worker clock so the song does not advance under the jingle.
local bgmHeld = false
local fanfareHold = false

local function ducked()
  -- Only PlayFanfare pauses BGM. SE_SELECT is also player 2 (SE2) and
  -- must not duck the map theme.
  if not fanfareHold then return false end
  local v = voices.fanfare
  return v.source ~= nil and v.songId ~= nil
end

local function holdBgm(hold)
  hold = hold and true or false
  local v = voices.bgm
  if hold then
    if v.source then pcall(v.source.pause, v.source) end
    if v.threaded and cmdCh then cmdCh:push({ cmd = "pause" }) end
    bgmHeld = true
  else
    if not bgmHeld then return end
    bgmHeld = false
    if v.threaded and cmdCh then cmdCh:push({ cmd = "resume" }) end
    if v.source then pcall(v.source.play, v.source) end
  end
end

local function syncBgmHold()
  local d = ducked()
  if not d then fanfareHold = false end
  holdBgm(d)
end

local function applyVolume(name)
  local v = voices[name]
  if not v.source then return end
  local s = spec(name)
  local scale = s.music and musicScale or effectScale
  if v.fade then scale = scale * v.fade.level end
  v.source:setVolume(BASE_VOLUME * scale)
end

local function applyAllVolumes()
  for _, name in ipairs(Mp2kAudio.VOICES) do applyVolume(name) end
end

-- A threaded voice has no source playing until its first buffer lands (~1
-- frame after the start), so "is this song already up?" cannot be answered by
-- Source:isPlaying alone or a second request would restart it.
local function voiceLive(v)
  if not v.source then return false end
  if v.threaded and not v.started then return true end
  local ok, playing = pcall(v.source.isPlaying, v.source)
  return ok and playing
end

local function fill(name, count)
  if name == "bgm" and bgmHeld then return end
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

local function clearVoice(name)
  local v = voices[name]
  if not v then return end
  if v.threaded and cmdCh then cmdCh:push({ cmd = "stop" }) end
  if v.source then pcall(v.source.stop, v.source) end
  v.engine, v.source, v.songId, v.fade = nil, nil, nil, nil
  v.threaded, v.gen, v.started, v.pending = nil, nil, nil, nil
  -- must be cleared with the rest: a leftover `true` from the last song would
  -- make pumpStreamed stop the next one the moment it was briefly not playing
  v.finishedSong = nil
end

function Mp2kAudio.stop(name)
  name = name or Mp2kAudio.DEFAULT_VOICE
  if name == "bgm" then bgmHeld = false end
  clearVoice(name)
  syncBgmHold()
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
  -- clearVoice, not stop: replacing a fanfare must not Continue BGM
  -- between the old jingle and the new one.
  clearVoice(name)
  local ok, source = pcall(love.audio.newQueueableSource,
    SAMPLE_RATE, 16, 2, queueDepth(name, false))
  if not ok or not source then return nil end
  v.engine = engine
  v.source = source
  v.songId = songId or true
  v.fade = nil
  v.threaded = nil
  v.started = true
  v.finishedSong = nil
  applyVolume(name)
  syncBgmHold()
  fill(name, spec(name).prefill)
  if spec(name).music and bgmHeld then
    pcall(source.pause, source)
  else
    source:play()
  end
  return source
end

-- ---------------------------------------------------------------------------
-- threaded music
-- ---------------------------------------------------------------------------

local musicGen = 0

-- Hand the song to the worker and return an empty source; playback starts in
-- update() once the first rendered buffer arrives.
local function playStreamed(data, songId, name, loop)
  local audio = data and data.audio
  local entry = audio and audio.songs and audio.songs[songId]
  if not entry or type(entry.header) ~= "number" then return nil end
  -- build the new source before tearing the old song down, so a failure here
  -- leaves the current music playing
  local ok, source = pcall(love.audio.newQueueableSource,
    SAMPLE_RATE, 16, 2, queueDepth(name, true))
  if not ok or not source then return nil end
  clearVoice(name)
  musicGen = musicGen + 1
  local v = voices[name]
  cmdCh:push({ cmd = "play", gen = musicGen, audio = slimAudio(data),
               header = entry.header, allowLoops = loop, songId = songId })
  v.engine = nil
  v.source = source
  v.songId = songId
  v.fade = nil
  v.threaded = true
  v.gen = musicGen
  v.started = false
  v.pending = nil
  v.finishedSong = nil
  applyVolume(name)
  syncBgmHold()
  return source
end

-- Move finished buffers from the worker into the Source, and start playback
-- once the first one lands.
local function pumpStreamed(name)
  local v = voices[name]
  if not (v.source and v.gen) then return end
  if not workerAlive() then
    -- worker gone: nothing more will arrive; leave what is queued playing out
    return
  end
  while true do
    local okFree, free = pcall(v.source.getFreeBufferCount, v.source)
    if not okFree or type(free) ~= "number" then return end
    local buf = v.pending
    if buf then v.pending = nil else buf = outCh:pop() end
    if not buf then break end
    if buf.gen ~= v.gen then
      -- stale buffer from a superseded song: drop it
    elseif buf.done then
      v.finishedSong = true
    elseif buf.error then
      require("src.core.Logger").warn("mp2k audio: %s", tostring(buf.error))
      v.finishedSong = true
    elseif buf.sd then
      if free > 0 then
        if not pcall(v.source.queue, v.source, buf.sd) then return end
      else
        v.pending = buf -- Source full; hold this one for the next frame
        break
      end
    end
  end
  local okFree, free = pcall(v.source.getFreeBufferCount, v.source)
  if not (okFree and type(free) == "number") then return end
  local queued = queueDepth(name, true) - free
  if not v.started then
    if queued > 0 then
      pcall(v.source.play, v.source)
      v.started = true
    end
    return
  end
  -- A QueueableSource stops on underrun; restart it while buffers remain.
  local okPlaying, playing = pcall(v.source.isPlaying, v.source)
  if okPlaying and not playing then
    if bgmHeld then
      -- m4aMPlayStop: do not restart the Source while a fanfare holds it.
    elseif queued > 0 then
      pcall(v.source.play, v.source)
    elseif v.finishedSong then
      Mp2kAudio.stop(name)
    end
  end
end

-- ---------------------------------------------------------------------------

local function startSong(data, songId, name, loop)
  if type(songId) ~= "number" then return nil end
  if spec(name).streamed and ensureWorker() then
    local source = playStreamed(data, songId, name, loop)
    if source then return source end
    -- the song is not in the table (or the source would not build): fall
    -- through to the inline path, which reports the same nil it always did
  end
  local engine = Mp2kSynth.newEngine(data, songId, { allowLoops = loop })
  if not engine then return nil end
  return Mp2kAudio.playVoice(name, engine, songId)
end

function Mp2kAudio.playSong(data, songId, loop)
  local v = voices.bgm
  if v.songId == songId and voiceLive(v) then
    return v.source
  end
  return startSong(data, songId, "bgm", loop ~= false)
end

-- gSongTable[].ms → gMPlayTable index. PlaySE of a player-0 dummy stays
-- off BGM. Missing cache entries default to SE1 (most field SEs).
function Mp2kAudio.songPlayer(data, songId)
  songId = tonumber(songId)
  if songId == nil then return 1 end
  local audio = data and data.audio
  local entry = audio and audio.songs and audio.songs[songId]
  local p = tonumber(entry and entry.player)
  if p == 1 or p == 2 or p == 3 then return p end
  return 1
end

function Mp2kAudio.effectVoice(data, songId)
  return Mp2kAudio.PLAYER_VOICE[Mp2kAudio.songPlayer(data, songId)] or "se"
end

-- Effects default to non-looping: a GOTO at the end of a jingle would
-- otherwise keep it going forever. Pass loop=true for intentional loops
-- (pokeruby SE_LOW_HEALTH / HandleLowHpMusicChange).
-- `name` nil/"se" follows the cart player. Explicit "fanfare"/"se3"/"cry"
-- keep the caller’s voice.
function Mp2kAudio.playEffect(data, songId, name, loop)
  if name == nil or name == "se" then
    name = Mp2kAudio.effectVoice(data, songId)
  end
  return startSong(data, songId, name, loop == true)
end

-- PlayFanfareByFanfareNum: m4aMPlayStop BGM, then m4aSongNumStart.
function Mp2kAudio.playFanfare(data, songId)
  fanfareHold = true
  local voice = Mp2kAudio.effectVoice(data, songId)
  local src = startSong(data, songId, voice, false)
  if not src then
    fanfareHold = false
    syncBgmHold()
  end
  return src
end

-- IsSEPlaying: SE1 or SE2, not SE3 (rain / low-HP) and not cry.
function Mp2kAudio.sePlaying()
  return Mp2kAudio.voicePlaying("se") or Mp2kAudio.voicePlaying("fanfare")
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
  if v.threaded then
    pumpStreamed(name)
    return
  end
  fill(name, spec(name).fill)
  local depth = queueDepth(name, false)
  -- A QueueableSource stops on underrun; restart it while buffers remain.
  if not (name == "bgm" and bgmHeld)
      and not v.source:isPlaying() and v.source:getFreeBufferCount() < depth then
    pcall(v.source.play, v.source)
  end
  if v.engine and v.engine:finished()
      and v.source:getFreeBufferCount() >= depth then
    Mp2kAudio.stop(name)
  end
end

function Mp2kAudio.update()
  for _, name in ipairs(Mp2kAudio.VOICES) do updateVoice(name) end
end

function Mp2kAudio.setVolumeLevel(level)
  musicScale = math.max(0, math.min(7, tonumber(level) or 7)) / 7
  applyAllVolumes()
end

-- Absolute 0..1 master for BGM. Game3:applyMusicVolume and music.volume
-- hooks pass Gen 1's VOLUME*optionScale (0.7 at full); applyVolume then
-- multiplies BASE_VOLUME * musicScale so the source lands on that value.
function Mp2kAudio.setVolume(vol)
  vol = tonumber(vol)
  if vol == nil then return end
  if vol < 0 then vol = 0 elseif vol > 1 then vol = 1 end
  musicScale = vol / BASE_VOLUME
  applyAllVolumes()
end

-- love.audio Source:setPan is -1..1. QueueableSource may lack it; never throw.
function Mp2kAudio.setPan(pan)
  pan = tonumber(pan)
  if pan == nil then return end
  if pan < -1 then pan = -1 elseif pan > 1 then pan = 1 end
  for _, name in ipairs(Mp2kAudio.VOICES) do
    local v = voices[name]
    if v and v.source and type(v.source.setPan) == "function" then
      pcall(v.source.setPan, v.source, pan)
    end
  end
end

function Mp2kAudio.setEffectVolumeLevel(level)
  effectScale = math.max(0, math.min(7, tonumber(level) or 7)) / 7
  applyAllVolumes()
end

function Mp2kAudio.currentSong() return voices.bgm.songId end

function Mp2kAudio.voiceSong(name)
  local v = voices[name or Mp2kAudio.DEFAULT_VOICE]
  return v and v.songId or nil
end

function Mp2kAudio.voicePlaying(name)
  local v = voices[name or Mp2kAudio.DEFAULT_VOICE]
  return v ~= nil and v.source ~= nil and v.songId ~= nil
end

function Mp2kAudio.isPlaying() return Mp2kAudio.voicePlaying("bgm") end

function Mp2kAudio.invalidate()
  Mp2kAudio.stopAll()
  if workerReady and cmdCh then cmdCh:push({ cmd = "invalidate" }) end
  Mp2kSynth.invalidate()
end

return Mp2kAudio
