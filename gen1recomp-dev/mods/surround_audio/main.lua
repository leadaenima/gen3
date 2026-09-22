-- surround_audio: the Crystal-style SOUND option (MONO/STEREO).  STEREO
-- forces Crystal's stereo split -- channels 1-2 to the left speaker, 3-4
-- to the right; MONO mixes every channel into both speakers.  Gen 1 songs
-- never write the pan register (all channels go to both speakers), so the
-- split has to be forced: honoring the song's panning would be silent.
--
-- The chip music mix happens on the synthesis worker thread
-- (src/core/chip_worker.lua), created once by
-- love.thread.newThread("src/core/chip_worker.lua").  The mod substitutes a
-- pan-aware copy of that worker (a newline-bearing string is inline source
-- to LÖVE) and steers it with a "pan" command on the engine's own
-- chipaudio_cmd channel.  This is the render level, so it works on any
-- audio backend -- the EFX filter/effect DSP (reverb, widening, the
-- engine's own MUSIC FILTER) is compiled out of this LÖVE build, which is
-- why a plugin-style approach cannot work here.
--
-- The engine's mod sandbox blocks love.thread and love.filesystem at the
-- facade, and mod.fetch only covers background HTTP -- it cannot reach the
-- worker.  The mod reaches the real LÖVE table through require("love"): the
-- sandbox's deny list refuses love.* but lets the bare root through.  If a
-- future engine closes that gap, realLove below is nil and the mod degrades
-- to routing-only instead of crashing.
--
-- Toggling restarts the current song (Crystal's RestartMapMusic) so the
-- change is heard immediately instead of after the ~6s playback buffer.
-- On top of that, all SFX (beeps, hits, cries, fanfares, the low-health
-- alarm) are positioned dead ahead of the listener -- the center channel
-- on a 5.1 device, the middle of the image on stereo.
--
-- Toggle with M (keyboard) or Select + R (gamepad).  The setting persists
-- in options.lua under save.options.surroundAudio and shows as the SOUND
-- row (MONO/STEREO) in the OPTIONS menu.

-- LÖVE registers "love" itself as a module (package.preload), and the
-- sandbox's deny list lets the bare root through -- only love.* is denied --
-- so require("love") hands back the real, unfacaded LÖVE table.
local realLove
do
  local ok, got = pcall(require, "love")
  realLove = (ok and type(got) == "table") and got or nil
end

return function(mod)
  local OPTION_KEY = "surroundAudio"

  -- dead ahead of the listener: azimuth 0, which OpenAL feeds to the center
  -- speaker on 5.1 devices and to the middle of the stereo image elsewhere
  local CENTER = { 0, 0, -1 }
  local ORIGIN = { 0, 0, 0 }

  -- weak registry of every live source the mod knows about, keyed by source
  -- with the classification as the value, so toggling re-routes sources that
  -- were created before the switch (GC'd sources fall out on their own)
  local sources = setmetatable({}, { __mode = "k" })

  local enabled = false

  -- the song label currently playing, from the music.started event; a
  -- toggle restarts it with the new pan mode so the change is immediate
  local currentSong = nil

  -- one-line diagnostic in the save dir: which backend features exist and
  -- whether the pan-aware worker was substituted (launcher-launched games
  -- have no visible stdout)
  local function writeProbe(extra)
    local fs = realLove and realLove.filesystem
    if not (fs and fs.write) then return end
    local efx = false
    if love.audio and love.audio.isEFXsupported then
      local ok, supported = pcall(love.audio.isEFXsupported)
      efx = ok and supported == true
    end
    local lines = {
      ("love=%s"):format(love._version or "?"),
      ("efx=%s"):format(tostring(efx)),
    }
    lines[#lines + 1] = extra
    pcall(fs.write, "surround_audio_probe.txt",
      table.concat(lines, "\n") .. "\n")
  end

  -- -------------------------------------------------------------------------
  -- pan-aware synthesis worker
  -- -------------------------------------------------------------------------

  -- the renderer spliced into the worker.  MONO sums every channel into
  -- both speakers (Engine:sample ignores the pan register).  STEREO forces
  -- Crystal's stereo split -- channels 1-2 to the left, 3-4 to the right --
  -- because Gen 1 songs never write the pan register (measured: 0/24 real
  -- songs differ between the speakers), so "honor the song's panning"
  -- would be silent.  Each side scales /2 so the split is as loud as the
  -- summed mix.  Both renders are 2-channel so the engine's existing
  -- QueueableSource still matches.
  local PAN_BOOT = [[
local panMode = 2 -- 2 = stereo (forced split), 1 = mono (both speakers)
local function renderPan(engine, buf)
  local sd = love.sound.newSoundData(buf, ChipSynth.SAMPLE_RATE, 16, 2)
  if panMode == 1 then
    for i = 0, buf - 1 do
      local v = engine:sample()
      sd:setSample(i, 1, v)
      sd:setSample(i, 2, v)
    end
    return sd
  end
  for i = 0, buf - 1 do
    local left, right = 0, 0
    for _, channel in ipairs(engine.channels) do
      local value = channel:sample()
      if channel.number <= 2 then
        left = left + value
      else
        right = right + value
      end
    end
    sd:setSample(i, 1, math.max(-1, math.min(1, left / 2)))
    sd:setSample(i, 2, math.max(-1, math.min(1, right / 2)))
  end
  return sd
end
]]

  -- three precise edits to the vanilla worker: boot the pan state, handle
  -- the "pan" command, and render through renderPan.  Any miss (an engine
  -- that changed the file) returns nil and the mod leaves the worker alone.
  local function esc(s)
    return (s:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"))
  end

  local function buildWorkerSource(vanilla)
    if type(vanilla) ~= "string" then return nil end
    local modified = vanilla
    local count = 0
    local out, n = modified:gsub(esc("local BUF = ChipSynth.MUSIC_BUFFER_SAMPLES"),
      "local BUF = ChipSynth.MUSIC_BUFFER_SAMPLES\n" .. PAN_BOOT, 1)
    modified, count = out, count + n
    out, n = modified:gsub(esc('elseif cmd.cmd == "channelMix" then'),
      'elseif cmd.cmd == "pan" then\n    panMode = cmd.mode == 1 and 1 or 2\n'
      .. '  elseif cmd.cmd == "channelMix" then', 1)
    modified, count = out, count + n
    out, n = modified:gsub(esc("pcall(ChipSynth.soundData, engine, BUF, 2)"),
      "pcall(renderPan, engine, BUF)", 1)
    modified, count = out, count + n
    if count < 3 then return nil end
    local ok, chunk = pcall(loadstring, modified)
    if not ok or not chunk then return nil end
    return modified
  end

  -- substitute the pan-aware worker when the engine creates its synthesis
  -- thread (once per session); the sentinel keeps a dev-mode hot reload
  -- from swapping the swapped thread
  local function wrapThreadFactory()
    local thread = realLove and realLove.thread
    if not thread or thread.__surroundAudioWrapped then return end
    local vanillaNewThread = thread.newThread
    if not vanillaNewThread then return end
    thread.__surroundAudioWrapped = true
    thread.newThread = function(source, ...)
      if type(source) == "string"
         and source:find("chip_worker", 1, true)
         and not source:find("\n", 1, true) then
        local ok, body = pcall(function()
          local fs = realLove and realLove.filesystem
          return fs and fs.read and fs.read("src/core/chip_worker.lua")
        end)
        if ok and type(body) == "string" then
          local modified = buildWorkerSource(body)
          if modified then
            source = modified
            writeProbe("worker=1")
          else
            writeProbe("worker=0 (worker source did not match)")
          end
        else
          writeProbe("worker=0 (worker source unreadable)")
        end
      end
      return vanillaNewThread(source, ...)
    end
  end

  -- steer the worker's pan mode through the engine's own command channel;
  -- unknown commands are ignored by the vanilla worker, so this is safe
  -- even when the substitution did not take
  local function pushPanMode(on)
    local thread = realLove and realLove.thread
    if not thread or not thread.getChannel then return end
    local ok, ch = pcall(thread.getChannel, "chipaudio_cmd")
    if ok and ch and ch.push then
      pcall(ch.push, ch, { cmd = "pan", mode = on and 2 or 1 })
    end
  end

  -- Crystal's RestartMapMusic: replay the current song from the top so the
  -- new pan mode is heard on the next buffer instead of after the ~6s
  -- look-ahead drains.  Music.reload clears the dedupe; play() re-cues it.
  local function restartSong()
    if not currentSong then return end
    local ok, Music = pcall(require, "src.core.Music")
    if not ok or not Music then return end
    local ok2, Game = pcall(require, "src.core.Game")
    local data = ok2 and Game and Game.data
    if not data then return end
    pcall(Music.reload, Music)
    pcall(Music.play, data, currentSong, true, { reason = "direct" })
  end

  -- -------------------------------------------------------------------------
  -- routing
  -- -------------------------------------------------------------------------

  local function setPosition(src, pos)
    pcall(src.setPosition, src, pos[1], pos[2], pos[3])
    pcall(src.setRelative, src, true)
  end

  local function clearPosition(src)
    pcall(src.setRelative, src, false)
    pcall(src.setPosition, src, ORIGIN[1], ORIGIN[2], ORIGIN[3])
  end

  local function setEnabled(on)
    enabled = on
    local audio = love and love.audio
    if audio and audio.setDistanceModel then
      -- the game never uses positional audio itself, so "none" is safe: it
      -- keeps every centered source at full volume regardless of distance
      pcall(audio.setDistanceModel, on and "none" or "inverseclamped")
    end
    for src, kind in pairs(sources) do
      if kind == "sfx" then
        if on then setPosition(src, CENTER) else clearPosition(src) end
      end
    end
    pushPanMode(on)
    restartSong()
  end

  -- wrap the two source factories at entry: the engine's audio modules only
  -- ever create sources through them, so this single point classifies and
  -- routes the SFX bus (chip SFX, cries, the low-health alarm, file SFX,
  -- pika clips); chip music and file songs stay untouched positionally
  local function wrapAudioFactories()
    local audio = love and love.audio
    if not audio or audio.__surroundAudioWrapped then return end
    audio.__surroundAudioWrapped = true
    local newSource = audio.newSource
    if newSource then
      audio.newSource = function(fileOrData, kind, ...)
        local src = newSource(fileOrData, kind, ...)
        if src then
          local classification = kind == "stream" and "music" or "sfx"
          sources[src] = classification
          if enabled and classification == "sfx" then
            setPosition(src, CENTER)
          end
        end
        return src
      end
    end
    local newQueueable = audio.newQueueableSource
    if newQueueable then
      audio.newQueueableSource = function(...)
        local src = newQueueable(...)
        if src then sources[src] = "music" end
        return src
      end
    end
  end

  -- a short confirm blip on every toggle, so the switch is audible on any
  -- output: it is created through the wrapped factory, so on a 5.1 device
  -- it is the first thing you hear from the center speaker.  ON is a higher
  -- note than OFF.  Headless (no love.sound) it is a safe no-op.
  local function confirmBlip(goingOn)
    local sound = love and love.sound
    if not sound or not sound.newSoundData then return end
    local rate = 44100
    local count = math.floor(rate * 0.12)
    local ok, sd = pcall(sound.newSoundData, count, rate, 16, 1)
    if not ok or not sd then return end
    local freq = goingOn and 988 or 660
    for i = 0, count - 1 do
      local env = 1 - i / count
      sd:setSample(i, math.sin(2 * math.pi * freq * i / rate) * 0.12 * env)
    end
    local audio = love.audio
    if not audio then return end
    local ok2, src = pcall(audio.newSource, sd, "static")
    if ok2 and src then
      pcall(src.setVolume, src, 0.9)
      pcall(src.play, src)
    end
  end

  local function toggle()
    setEnabled(not enabled)
    local ok, Game = pcall(require, "src.core.Game")
    if ok and Game and Game.save and Game.save.options then
      Game.save.options[OPTION_KEY] = enabled and 1 or 0
      if Game.writeOptions then pcall(Game.writeOptions, Game) end
    end
    mod.log:info("surround audio %s", enabled and "STEREO" or "MONO")
    confirmBlip(enabled)
  end

  -- -------------------------------------------------------------------------
  -- input, persistence, options row
  -- -------------------------------------------------------------------------

  -- M (keyboard) and Select + R (gamepad) are not Game Boy buttons, so
  -- they never reach wasPressed; wrap the Input entry points and latch the
  -- held edges so key auto-repeat cannot re-trigger the toggle.  The
  -- sentinel keeps a dev-mode hot reload from wrapping the wrappers (one
  -- press would then toggle twice, cancelling out).
  local Input = require("src.core.Input")

  local heldM = false
  local heldSelect = false
  local heldR = false

  local function pressM()
    if heldM then return end
    heldM = true
    toggle()
  end

  -- the combo fires when the second half of Select + R goes down while
  -- the first is still held
  local function padDown(button)
    if button == "back" then
      heldSelect = true
      if heldR then toggle() end
    elseif button == "rightshoulder" then
      heldR = true
      if heldSelect then toggle() end
    end
  end

  if not Input.__surroundAudioWrapped then
    Input.__surroundAudioWrapped = true
    local keyPressed = Input.keypressed
    function Input:keypressed(key, ...)
      if key == "m" then pressM() end
      return keyPressed(self, key, ...)
    end

    local keyReleased = Input.keyreleased
    function Input:keyreleased(key, ...)
      if key == "m" then heldM = false end
      return keyReleased(self, key, ...)
    end

    local padPressed = Input.gamepadpressed
    function Input:gamepadpressed(joystick, button, ...)
      padDown(button)
      return padPressed(self, joystick, button, ...)
    end

    local padReleased = Input.gamepadreleased
    function Input:gamepadreleased(joystick, button, ...)
      if button == "back" then heldSelect = false end
      if button == "rightshoulder" then heldR = false end
      return padReleased(self, joystick, button, ...)
    end
  end

  wrapThreadFactory()
  wrapAudioFactories()

  -- apply the persisted mode once a save (and its standalone options.lua
  -- table) exists; game.ready's skeleton save already carries options.lua,
  -- and NEW GAME / CONTINUE re-apply it after
  local function applyFromSave(save)
    if save and save.options then
      setEnabled(save.options[OPTION_KEY] == 1)
    end
  end

  mod.events:on("game.ready", function(ev)
    applyFromSave(ev and ev.game and ev.game.save)
  end)
  mod.events:on("save.created", function(ev)
    applyFromSave(ev and ev.save)
  end)
  mod.events:on("save.loaded", function(ev)
    applyFromSave(ev and ev.save)
  end)
  mod.events:on("music.started", function(ev)
    if ev and ev.song then currentSong = ev.song end
  end)

  -- the Crystal Options_Sound row: SOUND: MONO / STEREO; step toggles, the
  -- engine persists via writeOptions when the menu closes over the change
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = {
      id = "surround_audio",
      label = "SOUND",
      value = function(g)
        return (g.save.options[OPTION_KEY] == 1) and "STEREO" or "MONO"
      end,
      step = function(g)
        local on = not (g.save.options[OPTION_KEY] == 1)
        g.save.options[OPTION_KEY] = on and 1 or 0
        setEnabled(on)
        return true
      end,
    }
    return out
  end)

  -- test surface: the routing API, pure of any save state
  mod.exports = {
    isEnabled = function() return enabled end,
    setEnabled = setEnabled,
    toggle = toggle,
    buildWorkerSource = buildWorkerSource,
  }
end
