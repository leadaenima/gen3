-- Ruby MP2K playback: the sequencer's timing and command handling, and the
-- Game3 side that decides which song plays. Synthetic tracks only -- the
-- copyrighted .gba is not in git.
--   luajit tests/engine/ruby_mp2k_player_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby mp2k player")
local check = S.check
local eq = S.eq

local Mp2kSynth = require("src.core.Mp2kSynth")
local Game3 = require("src.core.Game3")
local Script = require("src.import.Gen3Script")

-- ------- 1. Clock table
-- gClockTable: even steps up to 24, then coarser. Waits index it directly
-- and notes are shifted by one, so N01 is a single tick and N96 is 96.
local CLOCK = Mp2kSynth.CLOCK
eq(CLOCK[0], 0, "W00 is no wait at all")
eq(CLOCK[24], 24, "the even run reaches 24")
eq(CLOCK[25], 28, "then it steps to 28")
eq(CLOCK[48], 96, "and tops out at 96, which is command 0xB0")
eq(CLOCK[1], 1, "N01 lasts one tick")
check(CLOCK[49] == nil, "there is no entry past 0xB0")

-- ------- 2. Tempo
-- The TEMPO byte is half the BPM. Each frame adds tempoD*tempoU/256 to a
-- counter and every 150 units is one tick, at 24 ticks per quarter note.
eq(Mp2kSynth.TICK_THRESHOLD, 150, "150 counter units per tick")
local function ticksPerSecond(bpm)
  return bpm * Mp2kSynth.FRAMES_PER_SECOND / Mp2kSynth.TICK_THRESHOLD
end
local quarters = ticksPerSecond(144) / 24
check(math.abs(quarters * 60 - 144) < 1,
  "144 BPM really does play 144 quarter notes a minute")

-- ------- 3. A synthetic cart
-- Laid out like the real thing: a SongHeader, a voicegroup, and tracks.
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local ROM = 0x08000000

-- header at 0, voicegroup at 0x40, track at 0x800
local function buildCart(track)
  local parts = {}
  parts[1] = string.char(1, 0, 0, 0) .. u32(ROM + 0x40) .. u32(ROM + 0x800)
  local cart = parts[1] .. string.rep("\0", 0x40 - #parts[1])
  -- One square-wave voice, so a note needs no sample data to sound. Game
  -- Boy envelope rates live in 0..15, and 0 means the step is instant.
  cart = cart .. string.char(1, 60, 0, 0) .. u32(2) .. string.char(0, 0, 15, 0)
  cart = cart .. string.rep("\0", 0x800 - #cart)
  cart = cart .. track
  return cart .. string.rep("\0", 0x900 - #cart)
end

local function stream(...)
  local out = {}
  for _, b in ipairs({ ... }) do out[#out + 1] = string.char(b) end
  return table.concat(out)
end

local function engineFor(track, options)
  return Mp2kSynth.newEngineFromBytes(buildCart(track), 0, 0, options or {})
end

local basic = engineFor(stream(0xBB, 0x48, 0xBD, 0x00, 0xD4, 0x3C, 0x64, 0xB1))
check(basic ~= nil, "an engine builds from a synthetic cart")
eq(#basic.tracks, 1, "with its one track")
eq(basic.voicegroup, 0x40, "and the voicegroup the header points at")
check(Mp2kSynth.newEngineFromBytes(buildCart(""), 0, nil) == nil,
  "a missing header offset builds nothing")

-- ------- 4. Running status
-- Only commands 0xBD and above latch. This is the bug that made every
-- track wedge: a wait latched, so the argument bytes after it were read as
-- another wait and the pointer never moved.
local track = basic.tracks[1]
basic:runTrack(track, 1)
eq(basic.tempoD, 0x48 * 2, "TEMPO 0x48 means 144 BPM")
eq(track.voice, 0, "VOICE was applied")
eq(track.running, 0xD4, "the note latched as the running command")

local latch = engineFor(stream(0xBD, 0x05, 0x90, 0xD4, 0x3C, 0x64, 0xB1))
local lt = latch.tracks[1]
latch:runTrack(lt, 1)
eq(lt.voice, 5, "VOICE ran")
check(lt.wait > 0, "and the wait after it stopped the run")
eq(lt.running, 0xBD, "a wait does not become the running command")
check(not lt.stopped, "so the track is still alive")

-- Argument bytes with no command in front repeat the last one. W01 is what
-- separates the two notes; W00 would let both run in the same pass.
local repeated = engineFor(stream(0xD4, 0x3C, 0x64, 0x81, 0x40, 0x64, 0xB1))
local rt = repeated.tracks[1]
repeated:runTrack(rt, 1)
eq(rt.lastKey, 0x3C, "the first note set the running key")
eq(rt.wait, 1, "and the run stopped on the wait after it")
repeated:tick()
eq(rt.lastKey, 0x40, "then the bare argument bytes played another note")

-- ------- 5. Waits and gates
local waiting = engineFor(stream(0x84, 0xD4, 0x3C, 0x64, 0xB1))
local wt = waiting.tracks[1]
waiting:runTrack(wt, 1)
eq(wt.wait, 4, "W04 waits four ticks")
for _ = 1, 4 do waiting:tick() end
check(wt.stopped, "after those ticks the track reaches FINE")

-- ------- 6. Flow control terminates
-- A track that jumps back to its own start must keep playing, and must not
-- spin forever inside one tick.
local looping = engineFor(stream(0xBB, 0x48, 0x84, 0xB2, 0x00, 0x08, 0x00, 0x08))
local loopTrack = looping.tracks[1]
for _ = 1, 200 do looping:tick() end
check(not loopTrack.stopped, "a looping track keeps running")
check(not looping:finished(), "so the song never reports finished")

local once = engineFor(stream(0xBB, 0x48, 0x84, 0xB2, 0x00, 0x08, 0x00, 0x08))
local onceTrack = once.tracks[1]
once.allowLoops = false
for _ = 1, 20 do once:tick() end
check(onceTrack.stopped, "with loops disabled the GOTO ends the track instead")

-- An unknown opcode stops the track rather than desyncing into noise.
local bogus = engineFor(stream(0xB6, 0x00, 0x00))
bogus:runTrack(bogus.tracks[1], 1)
check(bogus.tracks[1].stopped, "an unhandled command stops the track")

-- ------- 7. It makes sound
local sounding = engineFor(stream(0xBB, 0x60, 0xBE, 0x7F, 0xD4, 0x3C, 0x7F,
  0xB0, 0xB0, 0xB0, 0xB1))
local peak = 0
for _ = 1, Mp2kSynth.SAMPLE_RATE do
  local left, right = sounding:sampleStereo()
  peak = math.max(peak, math.abs(left), math.abs(right))
end
check(peak > 0.01, "a note actually renders a non-silent sample")
check(peak <= 1, "and never clips the output")

-- Silence is silent: no note means no signal.
local quiet = engineFor(stream(0xB0, 0xB0, 0xB1))
local quietPeak = 0
for _ = 1, 4096 do
  local left, right = quiet:sampleStereo()
  quietPeak = math.max(quietPeak, math.abs(left), math.abs(right))
end
eq(quietPeak, 0, "a track with no notes renders silence")

-- ------- 8. Song selection
-- MUS_NONE stops, and 0x7FFF marks the maps whose theme depends on where
-- the player is standing, so it must not restart anything.
eq(Game3.MUS_NONE, 0, "MUS_NONE")
eq(Game3.MUS_POSITION_DEPENDENT, 0x7FFF, "the position-dependent marker")

local game = setmetatable({ data = { audio = {} } }, { __index = Game3 })
eq(game:mapMusic({ music = 405 }), 405, "a map reports its header song")
eq(game:mapMusic({}), Game3.MUS_NONE, "a map with no music reports MUS_NONE")
check(game:playSong(Game3.MUS_POSITION_DEPENDENT) == nil,
  "the position-dependent marker plays nothing on its own")
check(game:playSong(nil) == nil, "and a missing id is ignored")

game.data.audio.named = { title = 413, vsWild = 457, vsTrainer = 459 }
eq(game:namedSong("vsWild"), 457, "named songs come from the registry")
eq(game:namedSong("nope"), nil, "an unknown name resolves to nothing")
eq(Game3.BATTLE_SONGS.wild, "vsWild", "wild battles use MUS_VS_WILD")
eq(Game3.BATTLE_SONGS.trainer, "vsTrainer", "trainer battles use MUS_VS_TRAINER")

-- savebgm / fadedefaultbgm round trip.
game.savedBgm = nil
game:saveBgm(405)
eq(game.savedBgm, 405, "savebgm remembers a song")

-- ------- 9. Script opcodes
-- 0x36..0x38 used to decode to nothing and be dropped at import.
eq(Script.FADENEWBGM, 0x36, "fadenewbgm opcode")
eq(Script.FADEOUTBGM, 0x37, "fadeoutbgm opcode")
eq(Script.FADEINBGM, 0x38, "fadeinbgm opcode")
eq(Script.PLAYBGM, 0x33, "playbgm opcode")
eq(Script.SAVEBGM, 0x34, "savebgm opcode")
eq(Script.FADEDEFAULTBGM, 0x35, "fadedefaultbgm opcode")

-- The runtime dispatches them onto the host.
local calls = {}
local host = {
  playSong = function(_, id) calls[#calls + 1] = "play:" .. tostring(id) end,
  saveBgm = function(_, id) calls[#calls + 1] = "save:" .. tostring(id) end,
  fadeDefaultBgm = function() calls[#calls + 1] = "default" end,
  fadeOutMapMusic = function(_, n) calls[#calls + 1] = "fade:" .. tostring(n) end,
}
Script.run(host, { { op = "playbgm", id = 405, save = 0 } })
Script.run(host, { { op = "savebgm", id = 413 } })
Script.run(host, { { op = "fadedefaultbgm" } })
Script.run(host, { { op = "fadeoutbgm", speed = 0 } })
eq(calls[1], "play:405", "playbgm reaches the host")
eq(calls[2], "save:413", "savebgm reaches the host")
eq(calls[3], "default", "fadedefaultbgm reaches the host")
eq(calls[4], "fade:nil", "a zero speed asks for the default fade")

-- ------- 10. Effects and fanfares
-- playse and playfanfare are ordinary songs on a different music player,
-- so they dispatch like playbgm but land on their own voice.
-- 0x2F..0x38 is one contiguous sound block in the script command table.
eq(Script.PLAYSE, 0x2F, "playse opcode")
eq(Script.WAITSE, 0x30, "waitse opcode")
eq(Script.PLAYFANFARE, 0x31, "playfanfare opcode")
eq(Script.WAITFANFARE, 0x32, "waitfanfare opcode")

local fx = {}
local fxHost = {
  playSe = function(_, id) fx[#fx + 1] = "se:" .. tostring(id) end,
  playFanfare = function(_, id) fx[#fx + 1] = "fanfare:" .. tostring(id) end,
  waitSe = function() fx[#fx + 1] = "waitse" end,
  waitFanfare = function() fx[#fx + 1] = "waitfanfare" end,
  scriptWaiting = function() return false end,
}
Script.run(fxHost, {
  { op = "playse", id = 5 }, { op = "waitse" },
  { op = "playfanfare", id = 370 }, { op = "waitfanfare" },
})
eq(table.concat(fx, ","), "se:5,waitse,fanfare:370,waitfanfare",
  "all four effect opcodes reach the host in order")

-- A wait that really is waiting suspends the script, the same way
-- waitmoncry does, rather than running on.
local suspended = false
local waitHost = {
  waitSe = function() suspended = true end,
  scriptWaiting = function() return suspended end,
  playSe = function() end,
}
local _, why = Script.run(waitHost,
  { { op = "playse", id = 5 }, { op = "waitse" }, { op = "playse", id = 9 } })
eq(why, "wait", "waitse suspends the script while the effect is sounding")

-- The voices are independent so a fanfare can play over the music.
local Mp2kAudio = require("src.core.Mp2kAudio")
check(Mp2kAudio.voicePlaying("se") == false, "nothing is on the effect voice")
local names = {}
for _, n in ipairs(Mp2kAudio.VOICES) do names[n] = true end
check(names.bgm and names.se and names.fanfare and names.cry,
  "there is a separate voice for music, effects, fanfares and cries")

-- ------- 11. Cries
-- SpeciesToCryId: below 251 the id is the index, the unused ?-species all
-- borrow Unown's, and Hoenn goes through a lookup because its cries were
-- recorded in a different order than the species were numbered.
local Audio = require("src.import.RomExtractorGen3Audio")
eq(Audio.CRY_UNOWN_ID, 200, "Unown's cry id")
eq(Audio.RUBY_US.cryCount, 388, "gCryTable has 388 entries")
eq((Audio.RUBY_US.cryTable2 - Audio.RUBY_US.cryTable) / Audio.VOICE_BYTES,
  Audio.RUBY_US.cryCount, "and gCryTable2 starts exactly one table later")

-- A cry voice is type 0x20, which is NOT the fixed-frequency bit (0x08).
-- Reading it as fixed would pin every cry to the sample's own rate.
local function cryCart(toneType)
  local pcm = {}
  for i = 1, 256 do pcm[i] = string.char((i * 7) % 256) end
  local tone = string.char(toneType, 60, 0, 0) .. u32(ROM + 0x20)
    .. string.char(255, 0, 255, 0)
  local wave = u32(0) .. u32(10512 * 1024) .. u32(0) .. u32(256)
  local cart = tone .. string.rep("\0", 0x20 - #tone) .. wave
    .. table.concat(pcm)
  return cart
end

local cry = Mp2kSynth.newCryEngineFromBytes(cryCart(0x20), 0, 0, {})
check(cry ~= nil, "a cry engine builds straight from a tone")
eq(#cry.tracks, 1, "with the one track the mixer needs")
check(cry.tracks[1].stopped, "which is stopped, since a cry has no sequence")
eq(#cry.dsChannels, 1, "and the note is already sounding")
check(cry.dsChannels[1].fixed == false,
  "type 0x20 is a pitched voice, not a fixed-rate one")

local fixedCry = Mp2kSynth.newCryEngineFromBytes(cryCart(0x28), 0, 0, {})
check(fixedCry.dsChannels[1].fixed == true, "0x28 does set the fixed bit")

-- It renders, and it stops on its own when the sample runs out: nothing
-- times a cry, so a channel that never died would wedge the voice.
local cryPeak, samples = 0, 0
while samples < Mp2kSynth.SAMPLE_RATE * 2 and not cry:finished() do
  samples = samples + 1
  cryPeak = math.max(cryPeak, math.abs(cry:sample()))
end
check(cryPeak > 0.01, "a cry renders a non-silent sample")
check(cry:finished(), "and ends by itself when the sample runs out")

check(Mp2kSynth.newCryEngine({ audio = {} }, 1) == nil,
  "a cache with no cry tables falls back rather than erroring")

-- ------- 12. A stopped track releases what it was holding
-- A GOTO with loops disabled used to stop the track without releasing its
-- note, so a one-shot effect sustained forever and never reported finished.
local hanging = engineFor(stream(0xBB, 0x60, 0xD4, 0x3C, 0x7F, 0xB2,
  0x00, 0x08, 0x00, 0x08))
hanging.allowLoops = false
for _ = 1, 400 do hanging:stepFrame() end
check(hanging:finished(), "a GOTO that ends the track also lets the note die")

S.finish()
