-- MP2K ("M4A"), the GBA sound driver Ruby uses. A song is a set of byte
-- streams -- one per track -- interpreted once per hardware frame, driving
-- up to 12 DirectSound channels that resample 8-bit PCM plus the four Game
-- Boy channels for accents.
--
-- ChipSynth is not reusable here: it interprets Game Boy channel programs,
-- and MP2K shares neither the command set, the timing model nor the sound
-- generation. What the two do share is the interface this module copies --
-- `newEngine`, `sampleStereo`, `finished`, `soundData` -- so the playback
-- pump and the buffer plumbing work the same way for both.
--
-- The data comes from RomExtractorGen3Audio, which ships one verbatim
-- 2.5 MB slice of the cart. A ROM pointer becomes an index into that slice
-- with `offset - base`, so this walks exactly the structures the GBA walks.
local Mp2kSynth = {}

local SAMPLE_RATE = 44100
-- The driver runs on vblank, not on a round 60 Hz, and every tempo and
-- envelope step is counted in those frames.
local FRAMES_PER_SECOND = 59.7275
local SAMPLES_PER_FRAME = SAMPLE_RATE / FRAMES_PER_SECOND

Mp2kSynth.SAMPLE_RATE = SAMPLE_RATE
Mp2kSynth.FRAMES_PER_SECOND = FRAMES_PER_SECOND
-- Smaller buffers than ChipSynth's 8192: this engine renders on the main
-- thread, so the prebuffer has to be cheap enough not to hitch the frame.
Mp2kSynth.MUSIC_BUFFER_SAMPLES = 2048
Mp2kSynth.MUSIC_BUFFER_COUNT = 32

local MAX_DIRECTSOUND = 12
local VOICE_BYTES = 12
local WAVEDATA_HEADER = 16
local ROM_BASE = 0x08000000

-- gClockTable: wait command 0x80+n lasts CLOCK[n] ticks, and note command
-- 0xD0+n lasts CLOCK[n+1]. Even spacing stops at 24.
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44, 48, 52, 54, 56, 60, 64, 66,
  68, 72, 76, 78, 80, 84, 88, 90, 92, 96,
}
Mp2kSynth.CLOCK = CLOCK

-- Tempo: each frame adds tempoD*tempoU/256 to a counter, and every time it
-- reaches 150 one tick passes. The TEMPO byte is half the BPM, so `BB 48`
-- is 144 BPM and 24 ticks make a quarter note.
local TICK_THRESHOLD = 150
local DEFAULT_TEMPO_U = 0x100
Mp2kSynth.TICK_THRESHOLD = TICK_THRESHOLD

local CMD_FINE = 0xB1
local CMD_GOTO = 0xB2
local CMD_PATT = 0xB3
local CMD_PEND = 0xB4
local CMD_REPT = 0xB5
local CMD_MEMACC = 0xB9
local CMD_PRIO = 0xBA
local CMD_TEMPO = 0xBB
local CMD_KEYSH = 0xBC
local CMD_VOICE = 0xBD
local CMD_VOL = 0xBE
local CMD_PAN = 0xBF
local CMD_BEND = 0xC0
local CMD_BENDR = 0xC1
local CMD_LFOS = 0xC2
local CMD_LFODL = 0xC3
local CMD_MOD = 0xC4
local CMD_MODT = 0xC5
local CMD_TUNE = 0xC8
local CMD_XCMD = 0xCD
local CMD_EOT = 0xCE
local CMD_TIE = 0xCF
local CMD_NOTE = 0xD0

local TONE_FIX = 0x08
local TONE_SPLIT = 0x40
local TONE_RHYTHM = 0x80

-- A tied note holds until an EOT rather than counting down a gate.
local GATE_TIED = -1

local MIX_SCALE = 0.28
local PATTERN_DEPTH = 3
-- A track that only ever waits zero ticks would spin forever; the real
-- driver is bounded by its frame, so bound the interpreter too.
local COMMANDS_PER_TICK = 128

local floor = math.floor

local blobCache, blobCacheKey

local function readBlob(audio)
  if not audio or type(audio.blob) ~= "string" then return nil end
  local key = audio.blob .. ":" .. tostring(audio.base)
  if blobCacheKey == key and blobCache then return blobCache end
  local raw
  local prefix = audio.programPrefix
  if prefix and prefix ~= "" then raw = love.filesystem.read(prefix .. audio.blob) end
  if not raw then raw = love.filesystem.read(audio.blob) end
  if not raw then return nil end
  blobCache, blobCacheKey = raw, key
  return raw
end

function Mp2kSynth.invalidate()
  blobCache, blobCacheKey = nil, nil
end

local Engine = {}
Engine.__index = Engine

-- Every read is by cart offset; `base` is where the shipped slice starts.
function Engine:u8(off)
  local i = off - self.base
  if i < 0 or i >= self.size then return 0 end
  return self.blob:byte(i + 1)
end

function Engine:s8(off)
  local v = self:u8(off)
  if v >= 0x80 then return v - 0x100 end
  return v
end

function Engine:u16(off)
  return self:u8(off) + self:u8(off + 1) * 256
end

function Engine:u32(off)
  return self:u16(off) + self:u16(off + 2) * 65536
end

-- Returns a cart offset, or nil when the pointer does not land in the slice.
function Engine:ptr(off)
  local p = self:u32(off)
  if p < ROM_BASE then return nil end
  local o = p - ROM_BASE
  if o < self.base or o >= self.base + self.size then return nil end
  return o
end

local function newTrack(start)
  return {
    ptr = start,
    wait = 0,
    running = nil,
    voice = 0,
    volume = 100,
    pan = 0,
    bend = 0,
    bendRange = 2,
    tune = 0,
    keyShift = 0,
    priority = 0,
    modDepth = 0,
    modType = 0,
    lfoSpeed = 22,
    lfoDelay = 0,
    lfoPhase = 0,
    lfoTimer = 0,
    stack = {},
    repeats = {},
    stopped = false,
    lastKey = 60,
    lastVelocity = 100,
  }
end

local function newBareEngine(blob, base, options)
  return setmetatable({
    blob = blob,
    base = base or 0,
    size = #blob,
    songId = options.songId,
    allowLoops = options.allowLoops ~= false,
    frameCountdown = 0,
    tempoD = 150,
    tempoU = DEFAULT_TEMPO_U,
    tempoC = 0,
    dsChannels = {},
    cgbChannels = {},
    tracks = {},
    frames = 0,
    done = false,
  }, Engine)
end

-- Build an engine straight from cart bytes. `base` is the offset the slice
-- starts at and `header` a SongHeader offset in the same space.
function Mp2kSynth.newEngineFromBytes(blob, base, header, options)
  options = options or {}
  if type(blob) ~= "string" or type(header) ~= "number" then return nil end

  local engine = newBareEngine(blob, base, options)

  local trackCount = engine:u8(header)
  if trackCount == 0 or trackCount > 16 then return nil end
  engine.voicegroup = engine:ptr(header + 4)
  if not engine.voicegroup then return nil end
  engine.priority = engine:u8(header + 2)
  for i = 0, trackCount - 1 do
    local start = engine:ptr(header + 8 + i * 4)
    if start then engine.tracks[#engine.tracks + 1] = newTrack(start) end
  end
  if #engine.tracks == 0 then return nil end
  return engine
end

function Mp2kSynth.newEngine(data, songId, options)
  options = options or {}
  local audio = data and data.audio
  if not audio or audio.engine ~= "mp2k" then return nil end
  local entry = audio.songs and audio.songs[songId]
  if not entry then return nil end
  local blob = readBlob(audio)
  if not blob then return nil end
  options.songId = songId
  return Mp2kSynth.newEngineFromBytes(blob, audio.base, entry.header, options)
end

Mp2kSynth.CRY_KEY = 60 -- every gCryTable entry is recorded at middle C

-- A cry is not in the song table: SetPokemonCryTone patches one ToneData
-- from gCryTable into a fixed one-note template. Rather than rebuild that
-- template, aim a bare engine's voicegroup at the cry's tone and strike the
-- note directly, which is all the template amounts to. The sample does not
-- loop, so the channel dies when it runs out and the engine reports
-- finished without anything having to time it.
function Mp2kSynth.newCryEngineFromBytes(blob, base, tone, options)
  options = options or {}
  if type(blob) ~= "string" or type(tone) ~= "number" then return nil end
  local engine = newBareEngine(blob, base, options)
  engine.voicegroup = tone
  -- One track, already stopped: there is no byte stream to sequence, it
  -- exists only to carry the volume and pan the mixer reads per channel.
  local track = newTrack(tone)
  track.stopped = true
  engine.tracks[1] = track
  engine:noteOn(track, 1, Mp2kSynth.CRY_KEY, options.velocity or 120, GATE_TIED)
  if #engine.dsChannels == 0 then return nil end
  return engine
end

function Mp2kSynth.newCryEngine(data, species, options)
  options = options or {}
  local audio = data and data.audio
  if not audio or audio.engine ~= "mp2k" then return nil end
  local base = options.alternate and audio.cryTable2 or audio.cryTable
  if not (base and type(audio.cries) == "table") then return nil end
  local id = audio.cries[tonumber(species) or 0]
  if type(id) ~= "number" then return nil end
  local blob = readBlob(audio)
  if not blob then return nil end
  return Mp2kSynth.newCryEngineFromBytes(blob, audio.base,
    base + id * VOICE_BYTES, options)
end

-- ------------------------------------------------------------------
-- Voices

-- Rhythm sets index their sub-voicegroup by the played key, key splits go
-- through a lookup table first. Either way the sub-voice's own key becomes
-- the pitch, which is how one drum kit plays a different sample per note.
function Engine:resolveVoice(track, key)
  local off = self.voicegroup + track.voice * VOICE_BYTES
  local typ = self:u8(off)
  if typ == TONE_RHYTHM or typ == TONE_SPLIT then
    local group = self:ptr(off + 4)
    if not group then return nil end
    local index = key
    if typ == TONE_SPLIT then
      local split = self:ptr(off + 8)
      if not split then return nil end
      index = self:u8(split + key)
    end
    if index > 127 then return nil end
    local sub = group + index * VOICE_BYTES
    local subType = self:u8(sub)
    if subType == TONE_RHYTHM or subType == TONE_SPLIT then return nil end
    return sub, self:u8(sub + 1)
  end
  return off, nil
end

local function noteFrequency(key)
  return 440 * 2 ^ ((key - 69) / 12)
end

function Engine:pitchOffset(track)
  local bend = (track.bend / 64) * track.bendRange
  local tune = track.tune / 64
  local vibrato = 0
  if track.modDepth > 0 and track.modType == 0
      and track.lfoTimer >= track.lfoDelay then
    vibrato = math.sin(track.lfoPhase) * (track.modDepth / 64)
  end
  return bend + tune + vibrato
end

function Engine:allocDirectSound()
  local channels = self.dsChannels
  for _, ch in ipairs(channels) do
    if ch.dead then return ch end
  end
  if #channels < MAX_DIRECTSOUND then
    local slot = {}
    channels[#channels + 1] = slot
    return slot
  end
  -- All 12 are sounding, so take the quietest one that is already
  -- releasing before touching anything still held.
  local best, bestScore
  for _, ch in ipairs(channels) do
    local score = (ch.stage == "release") and ch.env or (1000 + ch.env)
    if not bestScore or score < bestScore then best, bestScore = ch, score end
  end
  return best
end

function Engine:noteOn(track, index, key, velocity, gate)
  local playKey = key + track.keyShift
  if playKey < 0 then playKey = 0 elseif playKey > 127 then playKey = 127 end
  local voice, forcedKey = self:resolveVoice(track, playKey)
  if not voice then return end
  local typ = self:u8(voice)
  local kind = typ % 8
  local attack = self:u8(voice + 8)
  local decay = self:u8(voice + 9)
  local sustain = self:u8(voice + 10)
  local release = self:u8(voice + 11)
  local soundKey = forcedKey or playKey

  local ch
  if kind == 0 then
    local wave = self:ptr(voice + 4)
    if not wave then return end
    local size = self:u32(wave + 12)
    if size == 0 then return end
    ch = self:allocDirectSound()
    ch.kind = 0
    ch.data = wave + WAVEDATA_HEADER
    ch.size = size
    ch.loopStart = self:u32(wave + 8)
    ch.loops = self:u16(wave + 2) ~= 0
    -- WaveData.freq is the middle-C playback rate shifted left by 10.
    ch.midC = self:u32(wave + 4) / 1024
    -- Fixed frequency is bit 3 on its own, not "anything above 8": Ruby's
    -- cry voices are type 0x20, which is an ordinary pitched DirectSound.
    ch.fixed = math.floor(typ / TONE_FIX) % 2 == 1
    ch.pos = 0
  else
    if kind > 4 then return end
    ch = self.cgbChannels[kind] or {}
    self.cgbChannels[kind] = ch
    ch.kind = kind
    ch.phase = 0
    if kind == 1 or kind == 2 then
      ch.duty = self:u32(voice + 4) % 4
    elseif kind == 3 then
      ch.wave = self:ptr(voice + 4)
      if not ch.wave then return end
    else
      ch.lfsr = 0x7FFF
      ch.narrow = self:u32(voice + 4) % 2 == 1
      ch.noiseAcc = 0
    end
    -- CGB envelopes count frames per step on a 0..15 level, not the 0..255
    -- multiply-down the DirectSound channels use.
    ch.envCounter = 0
  end

  ch.track = index
  ch.key = soundKey
  -- A rhythm voice overrides the pitch, so EOT has to match on the key the
  -- track actually wrote, not the one the drum sample plays at.
  ch.noteKey = playKey
  ch.velocity = velocity
  ch.gate = gate
  ch.attack = attack
  ch.decay = decay
  ch.sustain = sustain
  ch.release = release
  ch.stage = "attack"
  ch.env = 0
  ch.dead = false
  -- A maxed DirectSound attack, or a zero CGB rate, is audible immediately
  -- rather than a frame later.
  if kind == 0 then
    if attack == 255 then ch.env = 255 end
  elseif attack <= 0 then
    ch.env = 15
    ch.stage = "decay"
  end
end

function Engine:noteOff(track, index, key)
  local function release(ch)
    if ch and not ch.dead and ch.track == index and ch.stage ~= "release" then
      if not key or ch.noteKey == key + track.keyShift or ch.gate == GATE_TIED then
        ch.stage = "release"
      end
    end
  end
  for _, ch in ipairs(self.dsChannels) do release(ch) end
  for _, ch in pairs(self.cgbChannels) do release(ch) end
end

-- ------------------------------------------------------------------
-- Sequencer

-- However a track ends, anything it is still holding has to be released,
-- or a sustaining note keeps the song from ever reporting finished and a
-- one-shot effect never frees its voice.
function Engine:stopTrack(track, index)
  track.stopped = true
  self:noteOff(track, index, nil)
end

function Engine:runTrack(track, index)
  local budget = COMMANDS_PER_TICK
  while track.wait == 0 and not track.stopped and budget > 0 do
    budget = budget - 1
    local cmd = self:u8(track.ptr)
    local at = track.ptr + 1
    if cmd < 0x80 then
      -- Running status: this byte is the first argument of the last command.
      cmd = track.running
      at = track.ptr
      if not cmd then self:stopTrack(track, index) break end
    elseif cmd >= CMD_VOICE then
      -- Only 0xBD and above latch. Waits and the flow-control commands
      -- below them must not, or the argument bytes after a wait would be
      -- read as another wait and the track would never advance.
      track.running = cmd
    end

    if cmd <= 0xB0 then
      track.wait = CLOCK[cmd - 0x80] or 0
      track.ptr = at
    elseif cmd == CMD_FINE then
      self:stopTrack(track, index)
    elseif cmd == CMD_GOTO then
      local target = self:ptr(at)
      if target and self.allowLoops then
        track.ptr = target
      else
        self:stopTrack(track, index)
      end
    elseif cmd == CMD_PATT then
      local target = self:ptr(at)
      if target and #track.stack < PATTERN_DEPTH then
        track.stack[#track.stack + 1] = at + 4
        track.ptr = target
      else
        track.ptr = at + 4
      end
    elseif cmd == CMD_PEND then
      local back = table.remove(track.stack)
      track.ptr = back or at
    elseif cmd == CMD_REPT then
      local count = self:u8(at)
      local target = self:ptr(at + 1)
      local key = at
      local seen = (track.repeats[key] or 0) + 1
      if target and (count == 0 or seen < count) then
        track.repeats[key] = seen
        track.ptr = target
      else
        track.repeats[key] = nil
        track.ptr = at + 5
      end
    elseif cmd == CMD_MEMACC then
      track.ptr = at + 3
    elseif cmd == CMD_XCMD then
      track.ptr = at + 2
    elseif cmd == CMD_PRIO then
      track.priority = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_TEMPO then
      self.tempoD = self:u8(at) * 2; track.ptr = at + 1
    elseif cmd == CMD_KEYSH then
      track.keyShift = self:s8(at); track.ptr = at + 1
    elseif cmd == CMD_VOICE then
      track.voice = self:u8(at) % 128; track.ptr = at + 1
    elseif cmd == CMD_VOL then
      track.volume = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_PAN then
      track.pan = self:u8(at) - 64; track.ptr = at + 1
    elseif cmd == CMD_BEND then
      track.bend = self:u8(at) - 64; track.ptr = at + 1
    elseif cmd == CMD_BENDR then
      track.bendRange = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_LFOS then
      track.lfoSpeed = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_LFODL then
      track.lfoDelay = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_MOD then
      track.modDepth = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_MODT then
      track.modType = self:u8(at); track.ptr = at + 1
    elseif cmd == CMD_TUNE then
      track.tune = self:u8(at) - 64; track.ptr = at + 1
    elseif cmd == CMD_EOT then
      local key = nil
      local nextByte = self:u8(at)
      if nextByte < 0x80 then key = nextByte; track.ptr = at + 1
      else track.ptr = at end
      self:noteOff(track, index, key)
    elseif cmd == CMD_TIE or cmd >= CMD_NOTE then
      -- Notes and ties take up to three and two arguments, but only while
      -- those bytes stay below 0x80; anything else reuses the last value.
      local key, velocity = track.lastKey, track.lastVelocity
      local extra = 0
      local p = at
      local b = self:u8(p)
      if b < 0x80 then key = b; p = p + 1; b = self:u8(p) end
      if b < 0x80 then velocity = b; p = p + 1; b = self:u8(p) end
      if cmd >= CMD_NOTE and b < 0x80 then extra = b; p = p + 1 end
      track.lastKey, track.lastVelocity = key, velocity
      track.ptr = p
      local gate = GATE_TIED
      if cmd >= CMD_NOTE then gate = (CLOCK[cmd - CMD_NOTE + 1] or 1) + extra end
      self:noteOn(track, index, key, velocity, gate)
    else
      -- Unknown opcode: stop rather than desync into noise.
      self:stopTrack(track, index)
    end
  end
end

function Engine:tick()
  for index, track in ipairs(self.tracks) do
    if track.wait > 0 then track.wait = track.wait - 1 end
    if track.wait == 0 then self:runTrack(track, index) end
  end
  local function step(ch)
    if ch and not ch.dead and ch.gate and ch.gate > 0 then
      ch.gate = ch.gate - 1
      if ch.gate == 0 then ch.stage = "release" end
    end
  end
  for _, ch in ipairs(self.dsChannels) do step(ch) end
  for _, ch in pairs(self.cgbChannels) do step(ch) end
end

local function stepDirectSoundEnvelope(ch)
  if ch.stage == "attack" then
    ch.env = ch.env + ch.attack
    if ch.env >= 255 then ch.env = 255; ch.stage = "decay" end
  elseif ch.stage == "decay" then
    ch.env = floor(ch.env * ch.decay / 256)
    if ch.env <= ch.sustain then ch.env = ch.sustain; ch.stage = "sustain" end
  elseif ch.stage == "sustain" then
    ch.env = ch.sustain
  else
    ch.env = floor(ch.env * ch.release / 256)
    if ch.env <= 0 then ch.env = 0; ch.dead = true end
  end
end

-- The Game Boy channels carry a 0..15 level (struct CgbChannel's
-- envelopeVolume) that moves one step at a time. envelopeCounter counts the
-- rate down and the level only moves when it runs out, so a bigger rate is
-- a slower slope -- and a rate of 0 means the move happens at once, which
-- is how the flat organ-like voices are written.
local INSTANT = "instant"

local function cgbStepDue(ch, rate)
  if rate <= 0 then return INSTANT end
  ch.envCounter = ch.envCounter + 1
  if ch.envCounter >= rate then ch.envCounter = 0; return true end
  return false
end

local function stepCgbEnvelope(ch)
  if ch.stage == "attack" then
    local due = cgbStepDue(ch, ch.attack)
    if due == INSTANT then
      ch.env = 15
      ch.stage = "decay"
    elseif due then
      ch.env = ch.env + 1
      if ch.env >= 15 then ch.env = 15; ch.stage = "decay" end
    end
  elseif ch.stage == "decay" then
    local due = cgbStepDue(ch, ch.decay)
    if due == INSTANT then
      ch.env = ch.sustain
      ch.stage = "sustain"
    elseif due then
      ch.env = ch.env - 1
      if ch.env <= ch.sustain then ch.env = ch.sustain; ch.stage = "sustain" end
    end
  elseif ch.stage == "sustain" then
    ch.env = ch.sustain
    if ch.env <= 0 then ch.dead = true end
  else
    local due = cgbStepDue(ch, ch.release)
    if due == INSTANT then
      ch.env = 0
      ch.dead = true
    elseif due then
      ch.env = ch.env - 1
      if ch.env <= 0 then ch.env = 0; ch.dead = true end
    end
  end
end

function Engine:stepFrame()
  self.frames = self.frames + 1
  self.tempoC = self.tempoC + self.tempoD * self.tempoU / 256
  while self.tempoC >= TICK_THRESHOLD do
    self.tempoC = self.tempoC - TICK_THRESHOLD
    self:tick()
  end
  for _, track in ipairs(self.tracks) do
    track.lfoTimer = track.lfoTimer + 1
    track.lfoPhase = track.lfoPhase + track.lfoSpeed / 256 * math.pi
  end
  for _, ch in ipairs(self.dsChannels) do
    if not ch.dead and ch.stage then stepDirectSoundEnvelope(ch) end
  end
  for _, ch in pairs(self.cgbChannels) do
    if not ch.dead and ch.stage then stepCgbEnvelope(ch) end
  end
  local live = false
  for _, track in ipairs(self.tracks) do
    if not track.stopped then live = true break end
  end
  if not live then
    local sounding = false
    for _, ch in ipairs(self.dsChannels) do
      if not ch.dead then sounding = true break end
    end
    if not sounding then
      for _, ch in pairs(self.cgbChannels) do
        if not ch.dead then sounding = true break end
      end
    end
    if not sounding then self.done = true end
  end
end

-- ------------------------------------------------------------------
-- Mixing

local DUTY = { [0] = 0.125, 0.25, 0.5, 0.75 }

function Engine:channelSample(ch)
  if ch.dead or not ch.stage then return 0 end
  local track = self.tracks[ch.track]
  if not track then return 0 end

  local amp
  if ch.kind == 0 then
    amp = (ch.env / 255)
  else
    amp = (ch.env / 15)
  end
  amp = amp * (ch.velocity / 127) * (track.volume / 127)
  if amp <= 0 then return 0 end

  local value = 0
  if ch.kind == 0 then
    local rate
    if ch.fixed then
      rate = ch.midC
    else
      rate = ch.midC * 2 ^ ((ch.key - 60 + self:pitchOffset(track)) / 12)
    end
    local pos = ch.pos
    local i = floor(pos)
    if i >= ch.size then
      if ch.loops then
        local span = ch.size - ch.loopStart
        if span <= 0 then ch.dead = true return 0 end
        pos = ch.loopStart + (pos - ch.size) % span
        i = floor(pos)
        ch.pos = pos
      else
        ch.dead = true
        return 0
      end
    end
    value = self:s8(ch.data + i) / 128
    ch.pos = pos + rate / SAMPLE_RATE
  else
    local freq = noteFrequency(ch.key + self:pitchOffset(track))
    if ch.kind == 1 or ch.kind == 2 then
      ch.phase = (ch.phase + freq / SAMPLE_RATE) % 1
      value = ch.phase < (DUTY[ch.duty] or 0.5) and 1 or -1
    elseif ch.kind == 3 then
      ch.phase = (ch.phase + freq / SAMPLE_RATE) % 1
      local step = floor(ch.phase * 32)
      local byteValue = self:u8(ch.wave + floor(step / 2))
      local nibble = (step % 2 == 0) and floor(byteValue / 16) or (byteValue % 16)
      value = (nibble - 7.5) / 7.5
    else
      ch.noiseAcc = ch.noiseAcc + freq * 8 / SAMPLE_RATE
      while ch.noiseAcc >= 1 do
        ch.noiseAcc = ch.noiseAcc - 1
        local lfsr = ch.lfsr
        local feedback = (lfsr % 2) ~= (floor(lfsr / 2) % 2)
        lfsr = floor(lfsr / 2)
        if feedback then lfsr = lfsr + 0x4000 end
        if ch.narrow then
          lfsr = lfsr % 0x40 + (feedback and 0x40 or 0) + floor(lfsr / 128) * 128
        end
        ch.lfsr = lfsr
      end
      value = (ch.lfsr % 2 == 0) and 1 or -1
    end
  end

  return value * amp
end

function Engine:sampleStereo()
  if self.frameCountdown <= 0 then
    self:stepFrame()
    self.frameCountdown = self.frameCountdown + SAMPLES_PER_FRAME
  end
  self.frameCountdown = self.frameCountdown - 1

  local left, right = 0, 0
  local function mix(ch)
    if not ch or ch.dead then return end
    local value = self:channelSample(ch)
    if value == 0 then return end
    local track = self.tracks[ch.track]
    local pan = track and track.pan or 0
    local l = (64 - pan) / 64
    local r = (64 + pan) / 64
    if l > 1 then l = 1 elseif l < 0 then l = 0 end
    if r > 1 then r = 1 elseif r < 0 then r = 0 end
    left = left + value * l
    right = right + value * r
  end
  for _, ch in ipairs(self.dsChannels) do mix(ch) end
  for _, ch in pairs(self.cgbChannels) do mix(ch) end

  left = left * MIX_SCALE
  right = right * MIX_SCALE
  if left > 1 then left = 1 elseif left < -1 then left = -1 end
  if right > 1 then right = 1 elseif right < -1 then right = -1 end
  return left, right
end

function Engine:sample()
  local left, right = self:sampleStereo()
  return (left + right) / 2
end

function Engine:finished()
  return self.done == true
end

function Mp2kSynth.soundData(engine, samples, channels)
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, channels)
  for index = 0, samples - 1 do
    if channels == 2 then
      local left, right = engine:sampleStereo()
      result:setSample(index, 1, left)
      result:setSample(index, 2, right)
    else
      result:setSample(index, engine:sample())
    end
  end
  return result
end

Mp2kSynth.Engine = Engine

return Mp2kSynth
