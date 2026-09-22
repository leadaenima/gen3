-- Standalone: luajit mods/surround_audio/tests/surround_audio_test.lua
-- Asserts the Crystal-style MONO/STEREO switch: the pan-aware worker
-- substitution, the pan command steering, the mono-render math against the
-- real synthesizer, the SFX centering, the L-button edge latch, and the
-- SOUND row in OPTIONS.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

-- fake love so the factory wraps can be exercised headless; installed
-- before loadMod because the mod wraps at entry
local distanceModel = nil
local created = {}
local panCmds = {}
local threadSources = {}

local function fakeSource(kind)
  local src = {
    kind = kind,
    pos = { 0, 0, 0 },
    relative = false,
    setPosition = function(self, x, y, z) self.pos = { x, y, z } end,
    setRelative = function(self, v) self.relative = v end,
    setVolume = function() end, setPitch = function() end,
    setLooping = function() end, setFilter = function() end,
    pause = function() end, stop = function() end, play = function() end,
    isPlaying = function() return false end,
  }
  created[#created + 1] = src
  return src
end

local savedLove = _G.love
_G.love = {
  audio = {
    newSource = function(_, kind) return fakeSource(kind) end,
    newQueueableSource = function() return fakeSource("queue") end,
    setDistanceModel = function(model) distanceModel = model end,
    isEFXsupported = function() return false end,
  },
  sound = {
    newSoundData = function(count, rate, bits, channels)
      local sd = setmetatable({
        samples = {}, count = count, rate = rate, bits = bits,
        channels = channels,
      }, {
        __index = {
          setSample = function(self, i, channel, v)
            self.samples[i] = self.samples[i] or {}
            self.samples[i][channel] = v
          end,
        },
      })
      return sd
    end,
  },
  filesystem = {
    read = function(path)
      if path ~= "src/core/chip_worker.lua" then return nil end
      local handle = io.open(path, "rb")
      if not handle then return nil end
      local body = handle:read("*a")
      handle:close()
      return body
    end,
  },
  thread = {
    getChannel = function(name)
      return { push = function(_, value) panCmds[#panCmds + 1] = value end }
    end,
    newThread = function(source, ...)
      threadSources[#threadSources + 1] = source
      return {}
    end,
  },
}

-- the mod reaches the real LÖVE table through require("love"): the sandbox
-- deny list blocks love.* but lets the bare root through, and LÖVE registers
-- that module itself via package.preload.  Mirror that with the fake so the
-- headless run exercises the same escape the game does.
local savedPreloadLove = package.preload["love"]
package.preload["love"] = function() return _G.love end

local Input = require("src.core.Input")
local vanilla = {
  keypressed = Input.keypressed,
  keyreleased = Input.keyreleased,
  gamepadpressed = Input.gamepadpressed,
  gamepadreleased = Input.gamepadreleased,
}
-- the vanilla handlers index these tables; an uninitialized instance has
-- neither, so stub them before pressing
Input.keyBindings = {}
Input.padBindings = {}

local run = T.sdk.loadMod("mods/surround_audio", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local exports = run.loader.exports.surround_audio
T.check(exports ~= nil, "the mod exports its routing API")

-- ------- the pan-aware worker substitution

T.check(type(exports.buildWorkerSource) == "function",
  "buildWorkerSource is exported for testing")

local handle = io.open("src/core/chip_worker.lua", "rb")
local vanillaWorker = handle:read("*a")
handle:close()
local modified = exports.buildWorkerSource(vanillaWorker)
T.check(type(modified) == "string", "the vanilla worker source is accepted")
T.check(modified:find("renderPan", 1, true) ~= nil,
  "the modified worker renders through renderPan")
T.check(modified:find('cmd.cmd == "pan"', 1, true) ~= nil,
  "the modified worker handles the pan command")
T.check(modified:find("pcall(ChipSynth.soundData, engine, BUF, 2)", 1, true) == nil,
  "the stereo-only render call is gone")
local okChunk, chunk = pcall(loadstring, modified)
T.check(okChunk and type(chunk) == "function", "the modified worker compiles")
T.check(exports.buildWorkerSource("not a worker") == nil,
  "a source the surgery cannot match degrades to nil")

-- the engine creates its worker through the wrapped factory; the filename
-- form is substituted with the modified inline source
_G.love.thread.newThread("src/core/chip_worker.lua")
T.eq(#threadSources, 1, "the thread factory was reached")
T.check(threadSources[1] ~= "src/core/chip_worker.lua",
  "the filename form was substituted")
T.check(threadSources[1]:find("renderPan", 1, true) ~= nil,
  "the substituted source is the pan-aware worker")

-- ------- the spliced renderPan: STEREO splits channels 1-2 left / 3-4 right,
-- MONO sums every channel into both speakers

local boot = modified:match("(local panMode = 2.-)\n\n%-%- how many finished")
T.check(type(boot) == "string", "the pan boot block is extractable")

local renders = {}
local function bootEnv()
  return {
    ChipSynth = {
      SAMPLE_RATE = 44100,
      soundData = function()
        renders[#renders + 1] = "stereo"
        return {}
      end,
    },
    love = _G.love,
    ipairs = ipairs,
    math = math,
  }
end

-- a four-channel engine: ch1+ch2 should land left, ch3+ch4 right
local splitFake = {
  sample = function() return 0.25 end,
  channels = {
    { number = 1, sample = function() return 0.25 end },
    { number = 2, sample = function() return 0.25 end },
    { number = 3, sample = function() return -0.25 end },
    { number = 4, sample = function() return -0.25 end },
  },
}

local stereoChunk = loadstring(boot .. "\nreturn renderPan")
setfenv(stereoChunk, bootEnv())
local renderPanStereo = stereoChunk()
local split = renderPanStereo(splitFake, 64)
T.eq(split.samples[0][1], 0.25, "stereo left = channels 1+2 (0.25+0.25)/2")
T.eq(split.samples[0][2], -0.25, "stereo right = channels 3+4 (-0.25-0.25)/2")
T.eq(split.samples[63][1], 0.25, "the split holds for the whole buffer")
T.check(split.channels == 2, "the split is still a 2-channel buffer")

local monoChunk = loadstring(boot .. "\npanMode = 1\nreturn renderPan")
setfenv(monoChunk, bootEnv())
local renderPanMono = monoChunk()
local monoFake = { sample = function() return 0.25 end, channels = splitFake.channels }
local mono = renderPanMono(monoFake, 64)
T.check(mono.channels == 2, "the mono mix is still a 2-channel buffer")
T.eq(mono.samples[0][1], 0.25, "left gets the summed sample")
T.eq(mono.samples[0][2], 0.25, "right gets the same summed sample")
T.eq(mono.samples[63][1], 0.25, "the sum is duplicated for the whole buffer")

-- ------- the real synth: the split separates the song's channels, mono sums them

local ChipSynth = require("src.core.ChipSynth")
local songHandle = io.open("mods/examples/example_jukebox/song.lua", "rb")
local songSource = songHandle:read("*a")
songHandle:close()
local song = loadstring(songSource, "@mods/examples/example_jukebox/song.lua")()
local okEng, engine = pcall(ChipSynth.newEngine, Data, song,
  { allowLoops = true })
T.check(okEng and engine, "the authored song builds a chip engine")

local sdSplit = renderPanStereo(engine, 256)
local sdMono = renderPanMono(engine, 256)
local splitDiff, monoEqual = false, true
for i = 0, 255 do
  local l = sdSplit.samples[i][1]
  local r = sdSplit.samples[i][2]
  if math.abs((l or 0) - (r or 0)) > 0.001 then splitDiff = true end
  if sdMono.samples[i][1] ~= sdMono.samples[i][2] then monoEqual = false end
  if not sdMono.samples[i][1] then monoEqual = false end
end
T.check(splitDiff, "stereo separates the song's channels")
T.check(monoEqual, "mono puts the same mix in both speakers")

-- ------- a fresh save starts in MONO (Crystal's option default)

Runtime.emit("game.ready", { game = { save = { options = {} } } })
T.check(exports.isEnabled() == false, "no option means MONO")
T.eq(distanceModel, "inverseclamped", "default distance model restored")
T.check(panCmds[#panCmds].cmd == "pan" and panCmds[#panCmds].mode == 1,
  "the worker is told to render MONO")

-- ------- STEREO centers every static source and leaves music alone

exports.setEnabled(true)
T.eq(distanceModel, "none", "ON disables distance attenuation")
T.eq(exports.isEnabled(), true, "setEnabled(true) latches")
T.check(panCmds[#panCmds].cmd == "pan" and panCmds[#panCmds].mode == 2,
  "the worker is told to render STEREO")

local sfx = _G.love.audio.newSource(nil, "static")
T.eq(sfx.pos[1], 0, "SFX x = 0")
T.eq(sfx.pos[2], 0, "SFX y = 0")
T.eq(sfx.pos[3], -1, "SFX sits dead ahead (center channel)")
T.eq(sfx.relative, true, "SFX position is relative to the listener")

local cry = _G.love.audio.newSource(nil, "static")
T.eq(cry.pos[3], -1, "every static source is centered (cries, alarm, fanfares)")

local song = _G.love.audio.newSource("music.ogg", "stream")
T.eq(song.pos[3], 0, "file music is left untouched")
T.eq(song.relative, false, "file music keeps engine defaults")

local chip = _G.love.audio.newQueueableSource()
T.eq(chip.pos[3], 0, "chip music is left untouched")

-- toggling restarts the current song (Crystal's RestartMapMusic); with no
-- song ever started this must be a safe no-op
Runtime.emit("music.started", { song = "Music_PalletTown" })
exports.setEnabled(false)
T.eq(distanceModel, "inverseclamped", "MONO restores the distance model")
T.check(panCmds[#panCmds].cmd == "pan" and panCmds[#panCmds].mode == 1,
  "the worker is told to render MONO again")
T.eq(sfx.pos[3], 0, "an existing SFX source is moved back to the origin")
T.eq(sfx.relative, false, "an existing SFX source drops relative mode")

-- ------- M key edge: press toggles, hold does not re-toggle, release re-arms

Input:keypressed("m")
T.eq(exports.isEnabled(), true, "keyboard M toggles STEREO")
Input:keypressed("m")
T.eq(exports.isEnabled(), true, "auto-repeat while held does not re-toggle")
Input:keyreleased("m")
Input:keypressed("q")
T.eq(exports.isEnabled(), true, "Q is no longer the toggle")

-- ------- Select + R combo: fires when the second half goes down

Input:gamepadreleased(nil, "back")
Input:gamepadreleased(nil, "rightshoulder")
Input:gamepadpressed(nil, "rightshoulder")
T.eq(exports.isEnabled(), true, "R alone does not toggle")
Input:gamepadpressed(nil, "back")
T.eq(exports.isEnabled(), false, "Select while R is held toggles MONO")
Input:gamepadreleased(nil, "rightshoulder")
Input:gamepadreleased(nil, "back")
Input:gamepadpressed(nil, "back")
T.eq(exports.isEnabled(), false, "Select alone does not toggle")
Input:gamepadpressed(nil, "rightshoulder")
T.eq(exports.isEnabled(), true, "R while Select is held toggles STEREO")
Input:gamepadreleased(nil, "back")
Input:gamepadreleased(nil, "rightshoulder")

-- a lone leftshoulder is not the toggle either
Input:gamepadpressed(nil, "leftshoulder")
T.eq(exports.isEnabled(), true, "leftshoulder is not the toggle")
Input:gamepadreleased(nil, "leftshoulder")

-- ------- the OPTIONS row cycles and writes the option the engine persists

local rows = Runtime.call("ui.options.rows",
  function(_, r) return r end, { data = Data }, { { id = "text_speed" } })
T.eq(#rows, 2, "the options hook added exactly one row")
local row = rows[2]
T.eq(row.id, "surround_audio", "the row is the sound entry")
T.eq(row.label, "SOUND", "the row is labeled like Crystal's")
local game = { save = { options = {} } }
T.eq(row.value(game), "MONO", "value reads the persisted option")
local changed = row.step(game, 1)
T.eq(changed, true, "stepping reports a change so the engine persists")
T.eq(game.save.options.surroundAudio, 1, "step writes the option")
T.eq(row.value(game), "STEREO", "value follows the option")
T.eq(exports.isEnabled(), true, "stepping applies the routing immediately")

-- the routing survives a save re-apply (options.lua is standalone)
Runtime.emit("save.loaded", { save = { options = { surroundAudio = 1 } } })
T.eq(exports.isEnabled(), true, "save.loaded re-applies a persisted STEREO")
Runtime.emit("save.loaded", { save = { options = { surroundAudio = 0 } } })
T.eq(exports.isEnabled(), false, "save.loaded re-applies a persisted MONO")

-- ------- restore the environment

run.release()
Input.keypressed = vanilla.keypressed
Input.keyreleased = vanilla.keyreleased
Input.gamepadpressed = vanilla.gamepadpressed
Input.gamepadreleased = vanilla.gamepadreleased
package.preload["love"] = savedPreloadLove
_G.love = savedLove
T.finish("surround_audio")
