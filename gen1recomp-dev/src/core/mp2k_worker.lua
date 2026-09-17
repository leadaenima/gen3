-- Mp2kAudio music synthesis worker (love.thread).  Runs the GBA MP2K synth
-- (src/core/Mp2kSynth.lua) off the main thread so a map music change never
-- stutters the render thread.  The Gen 1 peer is src/core/chip_worker.lua and
-- the protocol is deliberately the same shape.
--
-- Why this exists: Mp2kSynth costs ~1.8us per stereo sample, and filling a
-- song's playback queue from scratch renders the better part of a second of
-- audio.  On the main thread that landed as a hitch inside Game3:enterMap
-- (playMapMusic -> Mp2kAudio.playSong -> the prefill) plus a stutter tail over
-- the frames that followed, on every warp that changed the song.
--
-- Only the music voice streams from here.  Effects, fanfares and cries keep
-- rendering inline on the main thread: they are short, they want to be heard
-- on the frame they are asked for, and they were never the map-change cost.
--
-- Protocol -- main thread pushes command tables onto "mp2kaudio_cmd" and
-- drains produced buffers off "mp2kaudio_out":
--   cmd = "play"  { gen, audio = { blob, base, programPrefix }, header,
--                   allowLoops, songId }
--   cmd = "stop"                                       halt production
--   cmd = "invalidate"                                 drop the blob cache
--   cmd = "quit"                                        end the thread
-- out buffers carry the play's `gen` so the main thread can discard anything
-- left over from a superseded song:
--   { gen, sd = SoundData }   one rendered buffer
--   { gen, done = true }      the song ended (a non-looping jingle finished)
--   { gen, error = msg }      build/synth failed; main logs and gives up

require("love.thread")
require("love.timer")
require("love.sound")
require("love.filesystem")

-- Load the synth explicitly via love.filesystem: a fresh thread Lua state does
-- not necessarily carry the package searcher that resolves "src.core...".
local Mp2kSynth = assert(love.filesystem.load("src/core/Mp2kSynth.lua"))()

local cmdCh = love.thread.getChannel("mp2kaudio_cmd")
local outCh = love.thread.getChannel("mp2kaudio_out")

local BUF = Mp2kSynth.STREAM_BUFFER_SAMPLES
-- How many finished buffers may sit in the hand-off channel before the worker
-- pauses.  The playback depth itself lives in the main-thread Source; this
-- only bounds the worker's look-ahead (and its memory) between drains.
local LOOKAHEAD = 8

local gen = nil        -- active song generation, or nil when stopped
local engine = nil     -- the Mp2kSynth engine producing the current song
local finished = false -- the current song ran out (non-looping)

local function handle(cmd)
  if cmd.cmd == "play" then
    gen = cmd.gen
    finished = false
    engine = nil
    outCh:clear() -- drop any buffers left from the previous song
    local audio = cmd.audio or {}
    local blob = Mp2kSynth.blobFor(audio)
    if not blob then
      outCh:push({ gen = gen, error = "mp2k: no program blob" })
      finished = true
      return false
    end
    local ok, eng = pcall(Mp2kSynth.newEngineFromBytes, blob, audio.base,
                          cmd.header,
                          { allowLoops = cmd.allowLoops, songId = cmd.songId })
    if ok and eng then
      engine = eng
    else
      outCh:push({ gen = gen, error = tostring(ok and "unplayable song" or eng) })
      finished = true
    end
  elseif cmd.cmd == "stop" then
    gen = nil
    engine = nil
    finished = false
    outCh:clear()
  elseif cmd.cmd == "invalidate" then
    Mp2kSynth.invalidate()
  elseif cmd.cmd == "quit" then
    return true
  end
  return false
end

while true do
  -- drain every pending command first, so a stop/new-play is seen promptly
  local quit = false
  local cmd = cmdCh:pop()
  while cmd do
    if handle(cmd) then quit = true end
    cmd = cmdCh:pop()
  end
  if quit then break end

  if engine and not finished and gen and outCh:getCount() < LOOKAHEAD then
    local activeGen = gen
    local ok, sd = pcall(Mp2kSynth.soundData, engine, BUF, 2)
    if not ok then
      outCh:push({ gen = activeGen, error = tostring(sd) })
      finished = true
    else
      outCh:push({ gen = activeGen, sd = sd })
      if engine:finished() then
        outCh:push({ gen = activeGen, done = true })
        finished = true
      end
    end
  else
    -- nothing to do (idle, or the look-ahead is full): yield the core
    love.timer.sleep(0.001)
  end
end
