-- Ruby MP2K audio: song table layout and the track command decoder the
-- extractor and player both depend on. See RomExtractorGen3Audio.lua.
-- Offsets and synthetic streams only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_audio_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby mp2k audio")
local check = S.check
local eq = S.eq

local Audio = require("src.import.RomExtractorGen3Audio")
local CacheContract = require("src.import.CacheContract")

-- ------- 1. Song table
-- gSongTable is at 0x0845548C; song_table.inc lists 468 `song` entries of
-- {SongHeader*, u16 ms, u16 me}. Verified against the cart: 416 entries
-- carry a real header, the other 52 share dummy_song_header.
eq(Audio.RUBY_US.songTable, 0x45548C, "gSongTable file offset")
eq(Audio.RUBY_US.songCount, 468, "song_table.inc entry count")
eq(Audio.RUBY_US.songEntry, 8, "struct Song is 8 bytes")
eq(Audio.ROM_BASE, 0x08000000, "cart maps at 0x08000000")

eq(Audio.SONGS.title, 413, "MUS_TITLE")
eq(Audio.SONGS.intro, 414, "MUS_INTRO")
eq(Audio.SONGS.littleroot, 405, "MUS_LITTLEROOT")
eq(Audio.SONGS.vsWild, 457, "MUS_VS_WILD")
eq(Audio.SONGS.vsTrainer, 459, "MUS_VS_TRAINER")

-- ------- 2. Voicegroup shape
eq(Audio.VOICES_PER_GROUP, 128, "a voicegroup covers MIDI programs 0..127")
eq(Audio.VOICE_BYTES, 12, "struct ToneData is 12 bytes")
eq(Audio.WAVEDATA_HEADER, 16, "struct WaveData header before the PCM")
eq(Audio.TONE_CGB_MASK, 0x07, "low 3 bits pick the channel kind")
eq(Audio.TONE_FIX, 0x08, "TONEDATA_TYPE_FIX")
eq(Audio.TONE_SPLIT, 0x40, "TONEDATA_TYPE_SPL")
eq(Audio.TONE_RHYTHM, 0x80, "TONEDATA_TYPE_RHY")

-- ------- 3. Command lengths
-- A track is a byte stream: 0x80..0xB0 wait, 0xB1 ends it, the 0xB2..0xCD
-- band takes fixed arguments, and notes take up to three bytes that are
-- only arguments while they stay below 0x80.
local function stream(...)
  local bytes = {}
  for _, b in ipairs({ ... }) do bytes[#bytes + 1] = string.char(b) end
  return table.concat(bytes)
end

local function lenOf(bytes, running)
  return Audio.commandLength(bytes, 0, running)
end

eq(lenOf(stream(0x80)), 1, "W00 takes no arguments")
eq(lenOf(stream(0xB0)), 1, "W96 takes no arguments")
eq(lenOf(stream(0xB1)), 1, "FINE takes no arguments")
eq(lenOf(stream(0xB2, 0x00, 0x10, 0x00, 0x08)), 5, "GOTO carries a u32 address")
eq(lenOf(stream(0xB3, 0x00, 0x10, 0x00, 0x08)), 5, "PATT carries a u32 address")
eq(lenOf(stream(0xB4)), 1, "PEND takes no arguments")
eq(lenOf(stream(0xB5, 0x02, 0x00, 0x10, 0x00, 0x08)), 6,
  "REPT carries a count then a u32 address")
eq(lenOf(stream(0xB9, 0x00, 0x01, 0x02)), 4, "MEMACC takes three bytes")
eq(lenOf(stream(0xBB, 0x96)), 2, "TEMPO takes one byte")
eq(lenOf(stream(0xBD, 0x01)), 2, "VOICE takes one byte")
eq(lenOf(stream(0xCD, 0x08, 0x40)), 3, "XCMD takes a sub-command and a value")

-- Notes stop consuming at the next command byte, so the same opcode can be
-- one, two or three bytes long depending on what follows.
eq(lenOf(stream(0xD4, 0x3C, 0x64, 0x10)), 4, "note with key, velocity and gate")
eq(lenOf(stream(0xD4, 0x3C, 0x64, 0x80)), 3, "a wait ends the argument run")
eq(lenOf(stream(0xD4, 0x3C, 0xB1)), 2, "so does FINE")
eq(lenOf(stream(0xD4, 0xB1)), 1, "a note may carry no arguments at all")
eq(lenOf(stream(0xCE)), 1, "EOT with no key")
eq(lenOf(stream(0xCE, 0x3C)), 2, "EOT with a key")
eq(lenOf(stream(0xCF, 0x3C, 0x64)), 3, "TIE takes key and velocity")
eq(lenOf(stream(0xCF, 0x3C, 0x64, 0x10)), 3, "but never a gate")

-- Running status: a bare argument byte repeats the previous opcode.
eq(lenOf(stream(0x3C, 0x64), 0xD4), 2, "argument bytes repeat the last note")
eq(select(2, lenOf(stream(0x3C, 0x64), 0xD4)), 0xD4, "and it stays in effect")
eq(select(2, lenOf(stream(0xBD, 0x01))), 0xBD, "VOICE becomes the running opcode")
eq(select(2, lenOf(stream(0x90), 0xD4)), 0xD4, "a wait does not replace it")
check(lenOf(stream(0x3C)) == nil, "an argument byte with no running opcode stops")
check(lenOf(stream(0x3C), 0xB1) == nil, "FINE takes no running arguments")
check(lenOf("", nil) == nil, "running off the end stops the walk")

-- ------- 4. Track walking
-- The walker follows jumps so it can measure how far a song reaches. A
-- GOTO back to the start must terminate rather than spin.
local looping = stream(0xBB, 0x96, 0xD4, 0x3C, 0x64, 0xB2, 0x00, 0x00, 0x00, 0x08)
eq(Audio.walkTrack(looping, 0, {}), 10, "a self-looping track is measured once")
local ending = stream(0xBD, 0x01, 0xD4, 0x3C, 0xB1, 0xFF, 0xFF)
eq(Audio.walkTrack(ending, 0, {}), 5, "FINE stops before the trailing padding")

-- ------- 5. Header validation
-- dummy_song_header has no tracks, which is how the 52 placeholder slots
-- are told apart from real songs.
local function header(tracks, tone, parts)
  local out = { string.char(tracks, 0, 0, 0) }
  local function ptr(v)
    return string.char(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  out[#out + 1] = ptr(tone)
  for _, p in ipairs(parts) do out[#out + 1] = ptr(p) end
  return table.concat(out) .. string.rep("\0", 64)
end

-- The fixture stands in for a cart, so its pointers have to land inside it.
local good = header(2, 0x08000010, { 0x08000020, 0x08000030 })
local parsed = Audio.readSongHeader(good, 0)
check(parsed ~= nil, "a two-track header parses")
eq(parsed.trackCount, 2, "track count")
eq(parsed.voicegroup, 0x10, "voicegroup is stored as a file offset")
eq(parsed.tracks[2], 0x30, "so are the track pointers")
check(Audio.readSongHeader(header(0, 0x08000010, {}), 0) == nil,
  "dummy_song_header is rejected")
check(Audio.readSongHeader(header(17, 0x08000010, {}), 0) == nil,
  "more than 16 tracks is not a song")
check(Audio.readSongHeader(header(1, 0x02000000, { 0x08000020 }), 0) == nil,
  "a voicegroup outside the cart is not a song")
check(Audio.readSongHeader(header(1, 0x08000010, { 0x00000000 }), 0) == nil,
  "nor is a null track pointer")

-- ------- 6. Extraction contract
-- The blob is a verbatim slice of the cart, so the player resolves any ROM
-- pointer with `offset - base` and every goto target still lands correctly.
eq(Audio.BLOB_PATH, "assets/generated/audio/mp2k.bin", "blob path")
check(Audio.extract(nil) == nil, "extract needs cart bytes")
check(Audio.extract("short") == nil, "and refuses a truncated cart")
eq(Audio.toOffset(0x08123456), 0x123456, "ROM pointers convert to file offsets")

local required = CacheContract.requiredFilesFor("ruby")
local seen = {}
for _, path in ipairs(required) do seen[path] = true end
check(seen["data/generated/audio.lua"], "the registry is a required file")
check(seen[Audio.BLOB_PATH], "so is the blob")
eq(CacheContract.formatFor("ruby"), "rom-cache-v10-ruby41:",
  "ripe berry-tree frames bump the cache marker")

-- ------- 7. Cries
-- Cries are not in the song table: sound.c indexes gCryTable by a cry id,
-- and PlayCryInternal decrements the species before resolving it, so every
-- bound below is on the 0-based index rather than the species number.
eq(Audio.RUBY_US.cryTable, 0x452590, "gCryTable")
eq(Audio.RUBY_US.cryTable2, 0x4537C0, "gCryTable2")
eq(Audio.RUBY_US.cryCount, 388, "388 cries per table")
eq(Audio.CRY_TONE_TYPE, 0x20, "the cry macro's tone type")
eq(Audio.CRY2_TONE_TYPE, 0x30, "and cry2's")

-- The lookup only needs bytes for Hoenn, so the Kanto/Johto cases work
-- against an empty cart.
eq(Audio.cryId("", 1), 0, "Bulbasaur is the first entry")
eq(Audio.cryId("", 251), 250, "Celebi is still a direct index")
eq(Audio.cryId("", 252), Audio.CRY_UNOWN_ID,
  "the unused ?-species borrow Unown's cry")
eq(Audio.cryId("", 276), Audio.CRY_UNOWN_ID, "all the way to the last of them")
eq(Audio.cryId("", 0), nil, "species 0 is not a Pokemon")

-- Hoenn reads gSpeciesIdToCryId, because those cries were recorded in a
-- different order than the species were numbered: Treecko is species 277
-- but cry 273.
local map = {}
for _, id in ipairs({ 273, 274, 275, 270 }) do
  map[#map + 1] = string.char(id % 256, math.floor(id / 256))
end
local cart = string.rep("\0", Audio.RUBY_US.speciesToCryId) .. table.concat(map)
eq(Audio.cryId(cart, 277), 273, "Treecko's cry is not its species number")
eq(Audio.cryId(cart, 280), 270, "and Torchic's is lower still")

S.finish()
