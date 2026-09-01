-- Ruby's music is MP2K ("M4A"): sequenced tracks driving 12 DirectSound
-- channels plus the 4 Game Boy ones. That is nothing like Gen 1/2, where
-- ChipSynth interprets Game Boy channel programs, so none of that stack is
-- reusable here.
--
-- Everything the player needs -- gSongTable, the song headers, the track
-- byte streams, the voicegroups and the 8-bit PCM samples -- sits in one
-- 2.5 MB stretch of the cart. Rather than repack it (which would mean
-- rewriting every goto/pattern target), the extractor copies that stretch
-- verbatim and records where it started. The runtime then walks exactly
-- the structures the GBA walks, translating a ROM address with
-- `offset - base`. Nintendo's audio stays out of git; this is generated on
-- import from the player's own cart.
local GbaBin = require("src.import.GbaBin")
local CacheFs = require("src.import.CacheFs")

local Audio = {}

Audio.ROM_BASE = 0x08000000
Audio.BLOB_PATH = "assets/generated/audio/mp2k.bin"

-- US Ruby 1.0. `gSongTable` is at 0x0845548C; song_table.inc lists 468
-- entries of 8 bytes (SongHeader*, u16 music player, u16).
-- Cries are not songs: sound.c builds one on the fly from a ToneData in
-- gCryTable, indexed by cry id rather than by species. gCryTable2 is the
-- alternate set the game uses for the second of a pair of cries.
Audio.RUBY_US = {
  songTable = 0x45548C,
  songCount = 468,
  songEntry = 8,
  cryTable = 0x452590,
  cryTable2 = 0x4537C0,
  cryCount = 388,
  speciesToCryId = 0x1FDE6A,
}

-- SpeciesToCryId (pokemon_3.c) after PlayCryInternal's `species--`, so these
-- bounds are on the 0-based index, not on the species number.
Audio.CRY_DIRECT_MAX = 251 -- below this the cry id is the index itself
Audio.CRY_OLD_UNOWN_MAX = 275 -- the unused ?-slots all borrow Unown's cry
Audio.CRY_UNOWN_ID = 200
-- The `cry` and `cry2` macros (include/macros/music_voice.inc). Both are
-- pitched DirectSound -- 0x20 is not the fixed-frequency bit, that is 0x08.
Audio.CRY_TONE_TYPE = 0x20
Audio.CRY2_TONE_TYPE = 0x30
Audio.SPECIES_COUNT = 411

-- Songs the runtime hooks need, from include/constants/songs.h.
Audio.SONGS = {
  title = 413,
  intro = 414,
  introBattle = 442,
  littleroot = 405,
  vsWild = 457,
  vsTrainer = 459,
  victoryWild = 353,
  evolution = 377,
}

Audio.VOICES_PER_GROUP = 128
Audio.VOICE_BYTES = 12
Audio.WAVEDATA_HEADER = 16

-- ToneData.type: low 3 bits pick the channel kind, 0x08 marks a fixed-rate
-- DirectSound voice, 0x40 a key split and 0x80 a rhythm/drum set.
Audio.TONE_CGB_MASK = 0x07
Audio.TONE_FIX = 0x08
Audio.TONE_SPLIT = 0x40
Audio.TONE_RHYTHM = 0x80

-- MP2K track command lengths. 0x00..0x7F are argument bytes (a command
-- byte may be omitted entirely, repeating the previous one -- running
-- status). 0x80..0xB0 are waits and take none.
Audio.CMD_FINE = 0xB1
Audio.CMD_GOTO = 0xB2
Audio.CMD_PATT = 0xB3
Audio.CMD_PEND = 0xB4
Audio.CMD_REPT = 0xB5
Audio.CMD_MEMACC = 0xB9
Audio.CMD_XCMD = 0xCD
Audio.CMD_EOT = 0xCE
Audio.CMD_TIE = 0xCF
Audio.CMD_NOTE = 0xD0

-- Fixed-length commands, by opcode.
Audio.CMD_ARGS = {
  [0xB2] = 4, -- GOTO  <u32 address>
  [0xB3] = 4, -- PATT  <u32 address>
  [0xB4] = 0, -- PEND
  [0xB5] = 5, -- REPT  <u8 count> <u32 address>
  [0xB9] = 3, -- MEMACC
  [0xBA] = 1, -- PRIO
  [0xBB] = 1, -- TEMPO
  [0xBC] = 1, -- KEYSH
  [0xBD] = 1, -- VOICE
  [0xBE] = 1, -- VOL
  [0xBF] = 1, -- PAN
  [0xC0] = 1, -- BEND
  [0xC1] = 1, -- BENDR
  [0xC2] = 1, -- LFOS
  [0xC3] = 1, -- LFODL
  [0xC4] = 1, -- MOD
  [0xC5] = 1, -- MODT
  [0xC8] = 1, -- TUNE
  [0xCD] = 2, -- XCMD <u8 sub> <u8 value>
}
-- Variable-length commands take argument bytes while they stay below 0x80.
Audio.CMD_MAX_ARGS = {
  [0xCE] = 1, -- EOT  [key]
  [0xCF] = 2, -- TIE  [key [velocity]]
}
Audio.NOTE_MAX_ARGS = 3 -- key, velocity, gate

local function u8(data, off)
  if off < 0 or off >= #data then return nil end
  return data:byte(off + 1)
end

function Audio.isRomPtr(data, p)
  return p >= Audio.ROM_BASE and p < Audio.ROM_BASE + #data
end

function Audio.toOffset(p) return p - Audio.ROM_BASE end

-- How many argument bytes follow the command at `off`, and the opcode in
-- effect afterwards. `running` is the last real opcode seen on this track.
function Audio.commandLength(data, off, running)
  local cmd = u8(data, off)
  if not cmd then return nil end
  if cmd < 0x80 then
    -- Running status: these bytes are arguments for `running`.
    if not running then return nil end
    local max = (running >= Audio.CMD_NOTE) and Audio.NOTE_MAX_ARGS
      or Audio.CMD_MAX_ARGS[running] or Audio.CMD_ARGS[running]
    if not max or max == 0 then return nil end
    local n = 0
    while n < max do
      local b = u8(data, off + n)
      if not b or b >= 0x80 then break end
      n = n + 1
    end
    if n == 0 then return nil end
    return n, running
  end
  if cmd <= 0xB0 then return 1, running end -- wait
  if cmd == Audio.CMD_FINE then return 1, cmd end
  local fixed = Audio.CMD_ARGS[cmd]
  if fixed then return 1 + fixed, cmd end
  local max = Audio.CMD_MAX_ARGS[cmd]
    or (cmd >= Audio.CMD_NOTE and Audio.NOTE_MAX_ARGS)
  if not max then return nil end
  local n = 0
  while n < max do
    local b = u8(data, off + 1 + n)
    if not b or b >= 0x80 then break end
    n = n + 1
  end
  return 1 + n, cmd
end

-- Walk one track, following PATT/REPT/GOTO targets, and report the highest
-- byte it touches. A linear run always ends (FINE, GOTO or an unreadable
-- byte), so only jump targets need remembering -- marking every byte would
-- mean millions of table entries for no benefit.
function Audio.walkTrack(data, start, seen, limit)
  seen = seen or {}
  limit = limit or 0x20000
  local highest = start
  local stack = { start }
  while #stack > 0 do
    local off = table.remove(stack)
    local running = nil
    for _ = 1, limit do
      local len, nowRunning = Audio.commandLength(data, off, running)
      if not len then break end
      running = nowRunning
      local cmd = u8(data, off)
      if off + len > highest then highest = off + len end
      if cmd == Audio.CMD_GOTO or cmd == Audio.CMD_PATT
          or cmd == Audio.CMD_REPT then
        local at = (cmd == Audio.CMD_REPT) and (off + 2) or (off + 1)
        local target = GbaBin.u32(data, at)
        if Audio.isRomPtr(data, target) then
          local t = Audio.toOffset(target)
          if not seen[t] then
            seen[t] = true
            stack[#stack + 1] = t
          end
        end
      end
      if cmd == Audio.CMD_FINE or cmd == Audio.CMD_GOTO then break end
      off = off + len
    end
  end
  return highest
end

function Audio.readSongEntry(data, id)
  local u = Audio.RUBY_US
  local e = u.songTable + id * u.songEntry
  if e + u.songEntry > #data then return nil end
  return GbaBin.u32(data, e), GbaBin.u16(data, e + 4), GbaBin.u16(data, e + 6)
end

-- A SongHeader is real when its track count is sane and every pointer it
-- carries lands inside the cart. The 52 `dummy_song_header` slots have no
-- tracks and are skipped.
function Audio.readSongHeader(data, off)
  if off < 0 or off + 8 > #data then return nil end
  local tracks = u8(data, off)
  if not tracks or tracks == 0 or tracks > 16 then return nil end
  local tone = GbaBin.u32(data, off + 4)
  if not Audio.isRomPtr(data, tone) then return nil end
  local parts = {}
  for i = 0, tracks - 1 do
    local p = GbaBin.u32(data, off + 8 + i * 4)
    if not Audio.isRomPtr(data, p) then return nil end
    parts[i + 1] = Audio.toOffset(p)
  end
  return {
    trackCount = tracks,
    blockCount = u8(data, off + 1),
    priority = u8(data, off + 2),
    reverb = u8(data, off + 3),
    voicegroup = Audio.toOffset(tone),
    tracks = parts,
  }
end

-- One voicegroup: 128 programs of 12 bytes. Returns the nested voicegroups
-- a key split or rhythm set points at, plus every sample it reaches.
function Audio.scanVoicegroup(data, off, samples)
  local nested = {}
  for i = 0, Audio.VOICES_PER_GROUP - 1 do
    local o = off + i * Audio.VOICE_BYTES
    if o + Audio.VOICE_BYTES > #data then break end
    local typ = u8(data, o)
    local ptr = GbaBin.u32(data, o + 4)
    if typ == Audio.TONE_SPLIT or typ == Audio.TONE_RHYTHM then
      if Audio.isRomPtr(data, ptr) then
        nested[#nested + 1] = Audio.toOffset(ptr)
      end
    elseif typ % 8 == 0 then
      -- DirectSound: a WaveData header then `size` signed 8-bit samples.
      if Audio.isRomPtr(data, ptr) then
        local w = Audio.toOffset(ptr)
        local size = GbaBin.u32(data, w + 12)
        if size > 0 and size < 0x200000 and w + Audio.WAVEDATA_HEADER + size <= #data then
          samples[w] = size
        end
      end
    elseif typ % 8 == 3 then
      -- Programmable wave: 16 bytes of 4-bit wave RAM.
      if Audio.isRomPtr(data, ptr) then
        samples[Audio.toOffset(ptr)] = 0
      end
    end
  end
  return nested
end

-- SpeciesToCryId. The caller has already decremented, so `index` is
-- 0-based: below 251 the cry id is the index itself, the 25 unused
-- ?-species between Celebi and Treecko all share Unown's cry, and Hoenn
-- goes through gSpeciesIdToCryId because its cries were recorded in a
-- different order than the species were numbered.
function Audio.cryId(data, species)
  local u = Audio.RUBY_US
  local index = (tonumber(species) or 0) - 1
  if index < 0 then return nil end
  if index < Audio.CRY_DIRECT_MAX then return index end
  if index <= Audio.CRY_OLD_UNOWN_MAX then return Audio.CRY_UNOWN_ID end
  local at = u.speciesToCryId + (index - (Audio.CRY_OLD_UNOWN_MAX + 1)) * 2
  if at + 2 > #data then return nil end
  local id = GbaBin.u16(data, at)
  if id >= u.cryCount then return nil end
  return id
end

-- Every entry of both cry tables is the `cry`/`cry2` macro verbatim, so a
-- wrong offset shows up immediately as a bad type byte rather than as
-- silence at runtime.
function Audio.validCryTables(data)
  local u = Audio.RUBY_US
  for _, base in ipairs({ u.cryTable, u.cryTable2 }) do
    if base + u.cryCount * Audio.VOICE_BYTES > #data then return false end
    for i = 0, u.cryCount - 1 do
      local off = base + i * Audio.VOICE_BYTES
      local typ = GbaBin.u8(data, off)
      if typ ~= Audio.CRY_TONE_TYPE and typ ~= Audio.CRY2_TONE_TYPE then
        return false
      end
      if GbaBin.u8(data, off + 1) ~= 60 then return false end
      if not Audio.isRomPtr(data, GbaBin.u32(data, off + 4)) then return false end
    end
  end
  return true
end

-- The cry tables are not reachable from any song header, so their samples
-- have to be pulled into the span explicitly or the blob would stop short
-- of them.
function Audio.scanCries(data, samples)
  local u = Audio.RUBY_US
  local lo, hi = #data, 0
  for _, base in ipairs({ u.cryTable, u.cryTable2 }) do
    if base < lo then lo = base end
    local last = base + u.cryCount * Audio.VOICE_BYTES
    if last > hi then hi = last end
    for i = 0, u.cryCount - 1 do
      local ptr = GbaBin.u32(data, base + i * Audio.VOICE_BYTES + 4)
      if Audio.isRomPtr(data, ptr) then
        local w = Audio.toOffset(ptr)
        local size = GbaBin.u32(data, w + 12)
        if size > 0 and size < 0x200000
            and w + Audio.WAVEDATA_HEADER + size <= #data then
          samples[w] = size
        end
      end
    end
  end
  return lo, hi
end

-- Everything the player can reach, and the span of cart it occupies.
function Audio.scan(data)
  local u = Audio.RUBY_US
  local lo, hi = #data, 0
  local function touch(off, len)
    if off < lo then lo = off end
    local last = off + (len or 1)
    if last > hi then hi = last end
  end

  local songs, groups, samples = {}, {}, {}
  local live = 0
  local seenTargets = {}
  for id = 0, u.songCount - 1 do
    local ptr, player = Audio.readSongEntry(data, id)
    if ptr and Audio.isRomPtr(data, ptr) then
      local headerOff = Audio.toOffset(ptr)
      local header = Audio.readSongHeader(data, headerOff)
      if header then
        live = live + 1
        songs[id] = { header = headerOff, player = player,
          tracks = header.trackCount }
        touch(headerOff, 8 + header.trackCount * 4)
        groups[header.voicegroup] = true
        for _, t in ipairs(header.tracks) do
          touch(t, 1)
          touch(t, Audio.walkTrack(data, t, seenTargets) - t)
        end
      end
    end
  end

  -- Follow voicegroups, including the ones key splits and drum sets nest.
  local queue = {}
  for g in pairs(groups) do queue[#queue + 1] = g end
  local scanned = {}
  while #queue > 0 do
    local pending = {}
    for _, g in ipairs(queue) do
      if not scanned[g] then
        scanned[g] = true
        touch(g, Audio.VOICES_PER_GROUP * Audio.VOICE_BYTES)
        for _, nested in ipairs(Audio.scanVoicegroup(data, g, samples)) do
          if not scanned[nested] then pending[#pending + 1] = nested end
        end
      end
    end
    queue = pending
  end
  local cries = Audio.validCryTables(data)
  if cries then
    local clo, chi = Audio.scanCries(data, samples)
    touch(clo, 0)
    touch(chi, 0)
  end

  for off, size in pairs(samples) do
    touch(off, Audio.WAVEDATA_HEADER + size)
  end

  touch(u.songTable, u.songCount * u.songEntry)

  local groupCount, sampleCount, pcm = 0, 0, 0
  for _ in pairs(scanned) do groupCount = groupCount + 1 end
  for _, size in pairs(samples) do
    sampleCount = sampleCount + 1
    pcm = pcm + size
  end

  return {
    lo = lo, hi = hi, songs = songs, liveSongs = live,
    voicegroups = groupCount, samples = sampleCount, pcmBytes = pcm,
    cries = cries,
  }
end

-- Copy the reachable span verbatim and record where it came from, so the
-- runtime can resolve any ROM pointer with `offset - base`.
function Audio.extract(data)
  if type(data) ~= "string" then return nil end
  local u = Audio.RUBY_US
  if u.songTable + u.songCount * u.songEntry > #data then return nil end
  local scan = Audio.scan(data)
  if scan.liveSongs < 1 or scan.hi <= scan.lo then return nil end
  -- Page-align the span so the blob is easy to reason about.
  local base = scan.lo - (scan.lo % 4)
  local last = scan.hi + ((4 - scan.hi % 4) % 4)
  if last > #data then last = #data end
  local blob = data:sub(base + 1, last)
  local ok, err = CacheFs.write(Audio.BLOB_PATH, blob)
  if not ok then
    error("could not write " .. Audio.BLOB_PATH .. ": " .. tostring(err))
  end
  -- Resolve the species indirection at import so the runtime just needs
  -- `cryTable + cries[species] * 12`.
  local cries
  if scan.cries then
    cries = {}
    for species = 1, Audio.SPECIES_COUNT do
      local id = Audio.cryId(data, species)
      -- A hole would serialize as a truncated array and silently lose every
      -- species past it, so one bad lookup drops the whole set.
      if not id then cries = nil break end
      cries[species] = id
    end
  end

  return {
    blob = Audio.BLOB_PATH,
    base = base,
    size = #blob,
    romBase = Audio.ROM_BASE,
    songTable = u.songTable,
    songCount = u.songCount,
    songEntry = u.songEntry,
    songs = scan.songs,
    named = Audio.SONGS,
    cryTable = cries and u.cryTable or nil,
    cryTable2 = cries and u.cryTable2 or nil,
    cryCount = cries and u.cryCount or nil,
    cries = cries,
    voicegroups = scan.voicegroups,
    samples = scan.samples,
    engine = "mp2k",
  }
end

return Audio
