-- =====================================================================
-- AI ASSISTANTS: read AGENTS.md in this folder before editing.
--
-- It is two minutes and it covers the five ways this codebase has actually
-- broken -- all of which failed SILENTLY -- plus the tools/ suite that finds
-- them. Most relevant here: engine modules must be required at CALL time,
-- never at file scope, or you get the Gen 1 implementation on a Gold boot.
--   python3 tools/run_all.py --lua
-- =====================================================================

-- WEATHER FX -- dynamic weather for Gen1Recomp, overworld and battle.
--
-- =====================================================================
-- ARCHITECTURE
-- =====================================================================
--
-- THE PROBLEM.  Weather has to draw over whatever is rendering the world,
-- and the engine has several: the flat tile blit, the same blit under the
-- TILT mesh, the same again through the survey zoom, all of them in any of
-- the colour modes, optionally with the GBC FX grid on top -- and, if the
-- player has it, Dramatic Shape's voxel diorama, which replaces the world
-- pass entirely.  A mod that hooked one of those would break on the rest.
--
-- THE ANSWER is the render_pipelines registry, and specifically the fact
-- that ONE RECORD MAY DECLARE MORE THAN ONE STAGE.  This mod declares
-- both whole-frame stages, and uses a third hook for battles:
--
--   worldPresent(canvas, ctx)   over the finished WORLD image, before the
--                               UI composites -- but only when some
--                               pipeline produced a world image, i.e.
--                               only when a diorama-style renderer is on.
--                               Weather here lands under the dialog boxes.
--
--   present(canvas, ctx)        over the finished whole frame -- ALWAYS.
--                               This is the path for the flat renderer,
--                               tilt, zoom and every colour mode, because
--                               it runs on the finished composite and
--                               therefore cannot care how it was made.
--
--   battle.overlay(battle)      inside the battle's own 160x144 canvas.
--                               Not a pipeline stage at all: it is where
--                               battle weather belongs, because it is the
--                               only place that is in the battle's
--                               coordinates and passes through the
--                               battle's own palette handling.
--
-- Per frame exactly one whole-frame stage draws.  `worldPresent` sets a
-- flag; `present` sees it, clears it, and hands its canvas straight back.
-- Add a third-party world pipeline tomorrow and this mod supports it
-- unchanged, because NOTHING ON THE DRAW PATH NAMES ANY RENDERER.
--
-- INDEPENDENCE.  Version 1 borrowed Dramatic Shape's day/night clock,
-- which meant no night without that mod.  This one carries its own
-- (lib/TimeOfDay.lua) and defers to Dramatic Shape's only when it is
-- there -- so the Gold/Silver day/night grade, the `world.tod` value other
-- mods read, and the time-of-day weather weighting all work standalone.
--
-- THE LADDER IS THE WEATHER PICKER.  The registry hands a pipeline an
-- OFF/1/2/3 ladder with an OPTIONS row, a hotkey, persistence and a gate.
-- Rather than spend that on an intensity slider, level 1 is AUTO and
-- level 2 is CYCLE and levels 3+ pin a weather type, so the player picks the weather from the
-- menu they already use for TILT and ZOOM.
--
-- COST WHEN NOTHING IS HAPPENING IS ZERO, and `available` enforces it.
-- The engine re-reads it every frame and only allocates the present canvas
-- when some pipeline wants the stage (Pipelines.wantsPresent), so this
-- answers false whenever there is nothing to draw -- OFF, clear skies at
-- midday, indoors, or a full-screen menu over the world -- and on those
-- frames the engine's composite is the vanilla one, byte for byte.
--
-- FAILURE IS SURVIVABLE BY CONSTRUCTION.  A pipeline callback that throws
-- is retired for the session, attributed to this mod in the manager's
-- error feed, and the frame falls back to the vanilla path.  The worst
-- case for a bug anywhere in lib/ is that the player loses the weather,
-- never the game -- which is why the draw path is allowed to be the
-- interesting part and the state machine is written to be boring.
--
-- WHAT IS NOT TOUCHED BY NORMAL WEATHER. Encounters/scripts/save data stay
-- presentation-independent. The optional TORNADOES feature is the one explicit
-- exception: during its rare carry sequence it temporarily blocks new player
-- movement and uses the engine's normal visited-map warp entry point. Battles
-- are touched only through documented hooks.
-- Crystal 251 is detected by Battle.hostCrystal(); Weather FX battle damage/
-- seeding stands down while its visual layer remains independently controllable.
-- Carrying overworld weather into a battle is controlled explicitly by
-- BATTLE WEATHER FX / DMG plus `battle.seedFromOverworld`; there is no
-- hidden or inert ruleset gate.
--
-- =====================================================================

local mod = ...

-- ------- the mod namespace
--
-- lib/ modules require each other through V rather than package.path: a
-- mod directory is not on it, and may live inside a mounted .love archive
-- that plain require cannot reach.  Each module is loaded once, with V
-- passed in as its vararg (`local V = ...`).  The same shape Dramatic
-- Shape uses, deliberately -- an author who has read one of these mods can
-- read the other.

local V = { mod = mod, path = mod.path }

-- LuaJIT (what LÖVE 11 runs) has both `loadstring` and a 5.2-style `load`
-- that takes a string; plain 5.1 has only the former and 5.4 only the
-- latter.  Picking here means the same file compiles under the game, under
-- the modkit's validator, and under a bare interpreter running the tests.
local loadChunk = loadstring or load

local function chunkFor(rel)
  local source = mod:read(rel)
  if not source then
    error(("weather_fx: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  local chunk, err = loadChunk(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then
    error(("weather_fx: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return chunk
end

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local value = chunkFor("lib/" .. name .. ".lua")(V)
  modules[name] = value
  return value
end

local Config = V.require("Config")
local HostRuntime = V.require("HostRuntime")
Config.load()          -- first, because everything else reads it
local SafeCall = V.require("SafeCall")
V.safeBind = SafeCall.bind
-- Expose pcall-compatible root semantics. SafeCall.call itself expects a
-- leading scope argument, so assigning it directly shifts every caller's
-- arguments and silently turns valid functions into "non-function" failures.
V.safeCall = SafeCall.bind("root")
local safe = SafeCall.bind("main")

-- The engine's own pipeline registry and the live save options, both
-- protected and both optional: this is the only place in the mod that
-- WRITES engine state, and it does so on exactly one number (the weather
-- pipeline's ladder level) at the player's explicit request.
local function enginePipelines()
  local ok, P = safe(require, "src.render.Pipelines")
  if ok then return P end
  return nil
end

local function saveOptions()
  local ok, opts = safe(function()
    local Game = require("src.core.Game")
    return Game and Game.save and Game.save.options or nil
  end)
  if ok then return opts end
  return nil
end

local Types = V.require("Types")
local Settings = V.require("Settings")
local Scene = V.require("Scene")
local TOD = V.require("TimeOfDay")
local Seasons = V.require("Seasons")
local State = V.require("WeatherState")
local Quality = V.require("Quality")
local Particles = V.require("Particles")
local Lightning = V.require("Lightning")
local Ladder = V.require("Ladder")
local Draw = V.require("Draw")
local BattleDraw = V.require("BattleDraw")
local Compat = V.require("Compat")
local Battle = V.require("Battle")
local Interop = V.require("Interop")
local Backgrounds = V.require("Backgrounds")
local BattleField = V.require("BattleField")
local Follower = V.require("Follower")
local Encounters = V.require("Encounters")
local Tornado = V.require("Tornado")
local Funnel = V.require("Funnel")
local WindPlayer = V.require("WindPlayer")
local ConnectedWater = V.require("ConnectedWater")
local Audio = V.require("Audio")
local DebugHUD = V.require("DebugHUD")
local Benchmark = V.require("Benchmark")
local EngineRuntime = V.require("EngineRuntime")
-- EngineRuntime owns the former per-frame VoxelAtmos.update(dt) call and keeps
-- it ordered after WeatherState, celestial, wind and environment simulation.
EngineRuntime.configure({
  Seasons=Seasons, TOD=TOD, State=State, Draw=Draw, VoxelAtmos=V.require("VoxelAtmosBridge"),
  Follower=Follower, Tornado=Tornado, Audio=Audio, Settings=Settings, Lightning=Lightning,
})

-- WX_SFX_REGISTER: expose weather beds to the engine audio registry so
-- Sound.play / host volume tables can see them (optional; path play still works).
do
  local names = {
    rain = "assets/sounds/rain.ogg",
    rain_heavy = "assets/sounds/rain_heavy.ogg",
    heavy_storm = "assets/sounds/heavy_storm.ogg",
    storm = "assets/sounds/storm.ogg",
    wind = "assets/sounds/wind.mp3",
    wind_desert = "assets/sounds/wind_desert.mp3",
    thunder_clap = "assets/sounds/thunder_clap.mp3",
    thunder_roll = "assets/sounds/thunder_roll.mp3",
    thunder_zapdos = "assets/sounds/thunder_zapdos.mp3",
  }
  safe(function()
    if not (mod and mod.content and mod.content.sfx and mod.content.sfx.register) then return end
    for id, file in pairs(names) do
      safe(function()
        mod.content.sfx:register("WX_" .. id:upper(), { file = file })
      end)
    end
  end)
end

local Pokegear = V.require("Pokegear")

-- Optional 3D atmosphere bridge (Kanto path). Fail-closed at every step:
-- missing file, init failure, or incompatible voxel mod all leave a
-- no-op stub so Weather FX's normal post-process path is unchanged.
local VoxelAtmos = (function()
  local ok, bridge = safe(V.require, "VoxelAtmosBridge")
  if ok and bridge then
    safe(bridge.init)
    return bridge
  end
  return {
    active = function() return false end,
    handlesPrecipitation = function() return false end,
    handlesFog = function() return false end,
    handlesClouds = function() return false end,
    syncFromWeatherFx = function() end,
    update = function() end,
    invalidate = function() end,
    reason = function() return "bridge-unavailable" end,
  }
end)()

-- Optional engine APIs: a failure here must NOT prevent the mod from loading.
-- (Older builds / partial loaders have been seen without optional command APIs.)
do
  local function ensureOptions()
    local ok, err = safe(Settings.define)
    if not ok then
      safe(function() mod.log:warn("settings define failed: %s", tostring(err)) end)
    end
  end
  ensureOptions()
  safe(function()
    local SettingsMenu=V.require("SettingsMenu")
    if SettingsMenu and type(SettingsMenu.install)=="function" then SettingsMenu.install() end
  end)
  -- Host may rebuild option tables during boot; re-register only through the
  -- documented event bus. the old hook-bus event subscription is not a hook API and used to be
  -- hidden behind protected-call here, which made this look wired when it was a no-op.
  safe(function()
    if mod.events and mod.events.on then
      mod.events:on("game.ready", ensureOptions)
      mod.events:on("save.loaded", ensureOptions)
      mod.events:on("save.created", ensureOptions)
    end
  end)
  ensureOptions()
  local ok, err = safe(Encounters.install)
  if not ok then
    safe(function() mod.log:warn("encounters install failed: %s", tostring(err)) end)
  end
  ok, err = safe(Battle.install)
  if not ok then
    safe(function() mod.log:warn("battle install failed: %s", tostring(err)) end)
  end
end

-- ------- documented host integration hooks
--
-- These are feature plumbing, not optional decoration.  Earlier builds had the
-- implementations on disk but never connected them to the engine: AROUND battle
-- art had a Backgrounds.draw() function but no render.letterbox wrapper,
-- Scene.setViewport() claimed render.hud metrics that nobody supplied, and
-- TimeOfDay claimed to publish world.tod without a hook.  Keep the wrappers tiny
-- and delegate the semantics to testable module functions.
if mod.hooks and type(mod.hooks.wrap) == "function" then
  mod.hooks:wrap("render.hud", function(next_, game, viewport)
    Scene.setViewport(viewport)
    -- Base OPTIONS WEATHER must not depend on opening Mod Manager to become
    -- live. This always-running seam observes the engine ladder even if another
    -- UI mod/generation-specific menu replaced our decorated OPTIONS row.
    safe(Settings.pollWeatherLadder, game)
    local result = next_(game, viewport)
    local ok, err = safe(DebugHUD.draw, viewport)
    if not ok then
      safe(function() mod.log:warn("debug HUD draw failed: %s", tostring(err)) end)
    end
    local bok, berr = safe(Benchmark.draw, viewport)
    if not bok then
      safe(function() mod.log:warn("benchmark HUD draw failed: %s", tostring(berr)) end)
    end
    -- 8.1.58 relocation blackout: draw *after* Renderer:endFrame and every
    -- Weather FX HUD element. The normal present/worldPresent stage can be
    -- rebuilt during a real map swap, which allowed the destination frame to
    -- overwrite Funnel.draw's black rectangle. render.hud is the documented
    -- final game-frame seam, immediately before capture/presentation.
    local fok, ferr = safe(Funnel.drawBlackoutOverlay, viewport)
    if not fok then
      safe(function() mod.log:warn("tornado blackout overlay failed: %s", tostring(ferr)) end)
    end
    return result
  end)

  mod.hooks:wrap("render.letterbox", function(next_, ctx)
    local result = next_(ctx)
    local ok, err = safe(Backgrounds.draw, ctx)
    if not ok then
      safe(function() mod.log:warn("battle letterbox art failed: %s", tostring(err)) end)
    end
    return result
  end)

  mod.hooks:wrap("world.tod", function(next_, tod, ctx)
    local base = next_(tod, ctx)
    return TOD.worldTod(base)
  end)

end

-- ------- is there anything to draw?
--
-- The gate that keeps a clear midday free.  Any visible channel above a
-- threshold, a strike still in the air (which outlives the storm channel
-- by a fraction of a second), or a time-of-day grade that is not neutral.
-- `ash` belongs here: without it an ashfall on its own answered "nothing
-- to draw" and the pipeline was never eligible.
local VISIBLE_CHANNELS = { "rain", "snow", "hail", "sand", "ash", "debris",
                           "fog", "veil", "dim", "warm", "glare", "psy" }

local function anythingToDraw()
  local ch = Draw.channels()
  for i = 1, #VISIBLE_CHANNELS do
    local v = ch[VISIBLE_CHANNELS[i]]
    if type(v) == "number" and v > 0.004 then return true end
  end
  if Lightning.flash(Settings.get("lightning")) > 0.001 then return true end
  -- Keep the flat compositor alive long enough to finish the presentation-only
  -- three-second char/smoke reaction even if the storm channel eases away
  -- immediately after the impact.
  return Draw.npcLightningActive and Draw.npcLightningActive() or false
end

-- The rect the whole-frame stages draw into.  Shared by both pipelines so
-- the grade and the weather cannot disagree about where the screen is.
--
-- The engine reports two rects and hands this stage neither:
-- `gameWidth/gameHeight` from render.hud are the INTEGER-scaled 160x144
-- game rect, while the world is composited across the whole window through
-- a separate non-integer UI fit.  On a handheld the two differ a lot, so
-- the default is the whole canvas.
local function frameRect(canvas, ctx)
  local vp = Scene.viewport
  local cw, ch = canvas:getDimensions()
  local x, y, w, h
  if Config.get().coverage == "playfield" and vp then
    x, y, w, h = vp.x, vp.y, vp.w, vp.h
  else
    x, y, w, h = 0, 0, cw, ch
  end
  -- SCALE from the playfield height in canvas units, not ctx.scale: that
  -- is Sp, framebuffer PIXELS per GB pixel, and this canvas is in units,
  -- so the two differ by the DPI factor on a high-DPI panel.
  local scale = ((vp and vp.h) or h) / 144
  if not (scale > 0.05) then scale = (ctx and ctx.scale) or 1 end
  return x, y, w, h, scale
end

-- ------- the pipeline
--
-- One record, two whole-frame stages.  `drewThisFrame` is the handshake.

local drewThisFrame = false

mod.content.render_pipelines:register("weather", {
  label = "WEATHER",
  levels = State.LEVEL_LABELS,

  -- Below Dramatic Shape's voxel (20) and tiltshift (10) so three things
  -- fall out at once: the OPTIONS rows sort mode-then-post-process-then-
  -- weather, a world pipeline keeps the world pass, and the worldPresent
  -- fold reaches this pass AFTER a tilt-shift blur -- so rain stays sharp
  -- over a blurred diorama instead of being smeared into it.
  priority = 5,

  -- 0 is free: the engine claims 1-5 and F1/F2/F10, and Dramatic Shape
  -- claims 3 and 5-9.  Declared through the registry, which is checked
  -- after the engine's own display keys, so this can never shadow one --
  -- and Dramatic Shape's keypressed wrap passes unclaimed keys through.
  hotkey = "0",

  available = function()
    if not Particles.ready() then return false end
    if (State.level or 0) <= 0 then return false end
    local alpha = Scene.drawScale(Settings)
    if alpha <= 0 then return false end
    return anythingToDraw()
  end,

  -- Ticked whatever the level and whatever is on screen, which is what a
  -- weather clock wants: a storm keeps raging while the player is in a
  -- menu, in a battle, or inside a building, and is still there when they
  -- come out.  (At level 0, State.update returns immediately.)
  update = function(dt, level)
    if Settings.beginFrame then Settings.beginFrame() end
    Benchmark.beginUpdate()
    -- A mod-menu WEATHER edit is direct player authority. In particular, OFF
    -- must never become a one-way door: reconcile a pending OFF -> AUTO/named
    -- request into the engine ladder before WeatherState or render eligibility.
    if Settings.reconcileWeatherLadder then
      local reconciled=Settings.reconcileWeatherLadder(enginePipelines(),saveOptions(),level)
      if reconciled~=nil then level=reconciled end
    end
    -- Debug rain has to move the ENGINE's ladder, not a copy of it: the
    -- engine refuses to run any stage at level 0 before it asks this mod
    -- anything, so a shadow level would pin the weather and draw nothing.
    -- Done first, and the pushed value is used for the rest of the tick,
    -- so the switch takes effect on the frame it is flipped rather than
    -- the one after.
    if Settings.debugRain(Config) or Ladder.raisedByUs() then
      local pushed = Ladder.enforce(enginePipelines(), Settings.debugRain(Config),
        saveOptions())
      if pushed then level = pushed end
    end
    Scene.sample()
    Benchmark.preUpdate(dt)
    local sc = Scene and Scene.now or {}
    local pauseWeatherFrozen = sc.pauseMenu == true
      and tostring(Settings.get("pauseMenuWeather") or "animated"):lower() == "frozen"
    if Scene.updateWeatherAnimationClock then
      Scene.updateWeatherAnimationClock(dt, pauseWeatherFrozen, State and State.elapsed or 0)
    end
    local okRuntime, errRuntime, runtimeStage = EngineRuntime.update(dt, level, sc, {
      benchmarkActive = Benchmark.active(),
      animationPaused = pauseWeatherFrozen,
      afterClimate = function()
        -- Benchmark weather/time is intentionally temporary and non-persistent.
        -- Run after the authoritative WeatherState pass and before celestial,
        -- wind, environment, particles and audio consume this frame.
        Benchmark.enforce()
      end,
    })
    if not okRuntime then
      safe(function() mod.log:warn("EngineRuntime stage %s failed: %s", tostring(runtimeStage), tostring(errRuntime)) end)
      if runtimeStage == "climate" and type(State.ch) == "table" then
        for k in pairs(State.ch) do State.ch[k] = 0 end
      end
    end
    Benchmark.endUpdate(dt)
  end,

  -- THE DIORAMA PATH.  Only reached when a world pipeline produced a world
  -- image, so reaching it at all is the signal that the flat path must not
  -- run this frame.  The incoming canvas is drawn into directly rather
  -- than copied: it is rebuilt from scratch every frame by whoever made
  -- it, and an extra full-screen canvas per frame to avoid touching it
  -- would be the most expensive thing in this mod.
  --
  -- No text-box cut here: this stage composites UNDER the UI already, so
  -- the dialog box is drawn on top of the weather by the engine.
  worldPresent = function(canvas, ctx)
    -- Forced 2D is explicitly a final screen-space overlay. In voxel hosts the
    -- worldPresent canvas may be an intermediate world target that is later
    -- replaced/composited by the host. Drawing classic 2D weather there can
    -- therefore disappear completely while still setting drewThisFrame=true,
    -- which suppresses the real final-frame present pass. Leave ownership to
    -- present() when 2D OVERLAY is selected. FPV overrides force2dPresent(), so
    -- first person keeps the existing 3D world path.
    if Settings.force2dPresent and Settings.force2dPresent() then
      drewThisFrame = false
      return canvas
    end
    local w, h = canvas:getDimensions()
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    Benchmark.beginPresent()
    local ok = Draw.frame(0, 0, w, h, ctx and ctx.scale or 1, false)
    Benchmark.endPresent()
    -- Route/season banner only in present (final composite), never here
    love.graphics.setCanvas(previous)
    drewThisFrame = ok
    return canvas
  end,

  -- THE FLAT PATH -- and every other path the engine has, because this
  -- runs on the finished composite whatever produced it.  Scissored to the
  -- playfield the render.hud hook captured, so rain falls on the game and
  -- not in the black bars, and clipped above an open dialog box so it
  -- lands behind the text rather than on it.
  present = function(canvas, ctx)
    if drewThisFrame then
      drewThisFrame = false
      -- Still draw season/place banner on top when worldPresent already painted weather
      safe(function()
        local previous = love.graphics.getCanvas()
        love.graphics.setCanvas(canvas)
        Seasons.drawNotify()
        love.graphics.setCanvas(previous)
      end)
      return canvas
    end
    local x, y, w, h, scale = frameRect(canvas, ctx)
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    Benchmark.beginPresent()
    Draw.frame(x, y, w, h, scale, true)
    Benchmark.endPresent()
    safe(Seasons.drawNotify)
    love.graphics.setCanvas(previous)
    return canvas
  end,

  invalidate = function()
    Draw.invalidate()
    Audio.invalidate()
    BattleDraw.reset()
    Backgrounds.invalidate()
    Interop.reset()
    Quality.reset()
    VoxelAtmos.invalidate()
  end,
})

-- ------- hidden time-of-day grade pass
--
-- TIME OF DAY is a mod setting, not a second player-facing display ladder.
-- The old TIME pipeline row was removed because it duplicated that control,
-- but removing the pipeline also accidentally removed the actual flat-world
-- colour grade: Draw.grade still existed, yet no runtime stage called it.
--
-- Keep a tiny present-only pipeline internally enabled and hide its generated
-- OPTIONS row below. Pipelines.update() ticks records even at level 0, so the
-- first update can raise this internal rung before the same frame's present
-- eligibility check. TIME OF DAY=OFF is then enforced by `available`, while
-- weather itself may be OFF without taking the clock/grade with it.
local TIME_PIPELINE_ID = "weather_time_grade"
local timeDrewThisFrame = false

mod.content.render_pipelines:register(TIME_PIPELINE_ID, {
  label = "WX TIME",
  levels = { "OFF", "ON" },
  priority = 6, -- immediately under the weather particles in composition order

  update = function()
    local P = enginePipelines()
    if P and P.level and P.setLevel and (P.level(TIME_PIPELINE_ID) or 0) <= 0 then
      P.setLevel(TIME_PIPELINE_ID, 1)
    end
  end,

  available = function()
    if not (Scene.now and Scene.now.visible == "world") then return false end
    if Settings.get("daytime") == "off" then return false end
    local ok, mr = safe(function() return TOD.grade(Scene.now.indoors) end)
    return ok and mr ~= nil
  end,

  worldPresent = function(canvas, ctx)
    local w, h = canvas:getDimensions()
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    local ok, drew = safe(Draw.grade, 0, 0, w, h, Scene.now.indoors)
    love.graphics.setCanvas(previous)
    timeDrewThisFrame = ok and drew == true
    return canvas
  end,

  present = function(canvas, ctx)
    if timeDrewThisFrame then
      timeDrewThisFrame = false
      return canvas
    end
    -- Flat present is after the native textbox/banner. Keep the world grade
    -- alive in the uncovered playfield while leaving that UI rectangle intact.
    -- Unknown/full-screen UI states are still rejected by Scene.visible.
    if not (Scene.now and Scene.now.visible == "world") then return canvas end
    local x, y, w, h = frameRect(canvas, ctx)
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    safe(Draw.gradeFrame, x, y, w, h, Scene.now.indoors, true)
    love.graphics.setCanvas(previous)
    return canvas
  end,
})


-- TIME has no player-facing render-pipeline ladder. The hidden grade pass
-- above exists only to give the TIME OF DAY mod setting a compositor that is
-- independent of WEATHER; its generated engine row is filtered below.


-- boot. What differs is who asks for them. Gen 1's options menu calls
-- `Pipelines.rows(game)` itself and splices the result in after TILT
-- (src/ui/OptionsMenu.lua). Gen 2's does not call it at all
-- (src/ui/gen2/OptionsMenu.lua) -- it raises `ui.options.rows` and takes
-- what comes back. So the row has to be handed to it.
--
-- GEN 2 ONLY, deliberately. On Gen 1 the engine already splices pipeline rows;
-- adding WEATHER here as well would show it twice. TIME is no longer a render
-- pipeline row; its control lives only in the Weather FX mod settings.
--
-- OURS ONLY, not every registered pipeline. `Pipelines.rows` returns a row
-- for every pipeline any mod registered, so appending the lot would mean two
-- mods applying this same fix each add the other's rows. Filtering to the
-- single pipeline id this mod owns keeps the fix additive.
--
-- And it is idempotent: if a later engine build starts splicing pipeline
-- rows into Gold's options the way Gen 1 does, the ids will already be in
-- the incoming list and nothing is added. That check is why this cannot
-- become a duplicate-row bug later.
-- Gen 2 OPTIONS: additive WEATHER row only. Hardened for other UI mods:
--   * always call next_ first (preserve full chain)
--   * never mutate the table other mods returned
--   * only append our pipeline id if missing
--   * any failure → return prior rows unchanged (menu must not break)
if not mod._wxOptionsRowsWrapped then
  mod._wxOptionsRowsWrapped = true
  local OUR_ID = "pipeline:weather"
  local HIDDEN_TIME_ID = "pipeline:" .. TIME_PIPELINE_ID

  -- The engine owns the OPTIONS pipeline row, while Weather FX owns the Mod
  -- Manager WEATHER row. Decorate the engine row so a d-pad step immediately
  -- mirrors into Weather FX instead of waiting for a later climate tick. This
  -- keeps both menus visibly synchronized even while paused/in another menu.
  local function unifiedWeatherRow(row)
    if type(row) ~= "table" or row.id ~= OUR_ID or row.__weatherFxUnified then return row end
    local out = {}; for k,v in pairs(row) do out[k]=v end
    out.__weatherFxUnified = true
    local rawStep = row.step
    out.step = function(game, dir)
      local ret = true
      if type(rawStep) == "function" then ret = rawStep(game, dir) end
      safe(function()
        local P = require("src.render.Pipelines")
        local level = P and type(P.level)=="function" and P.level("weather") or nil
        if level ~= nil and Settings and Settings.handleWeatherLadderChanged then
          Settings.handleWeatherLadderChanged(level, game)
        end
      end)
      if ret == nil then return true end
      return ret
    end
    return out
  end

  mod.hooks:wrap("ui.options.rows", function(next_, game, rows)
    local out = rows
    local okNext, nextOut = safe(function()
      if type(next_) == "function" then return next_(game, rows) end
      return rows
    end)
    if okNext then out = nextOut end
    if type(out) ~= "table" then return out end

    local ok, merged = safe(function()
      -- Every render pipeline normally generates an OPTIONS row. TIME OF DAY
      -- already has one authoritative control in the mod settings, so remove
      -- only the internal compositor row and leave every other mod's rows
      -- untouched. Gen 1 reaches this hook after Pipelines.rows was spliced;
      -- Gen 2 reaches it with its native rows.
      local filtered, present = {}, {}
      for _, row in ipairs(out) do
        if type(row) == "table" and row.id == HIDDEN_TIME_ID then
          -- deliberately hidden internal implementation detail
        else
          local kept = unifiedWeatherRow(row)
          filtered[#filtered + 1] = kept
          if type(kept) == "table" and type(kept.id) == "string" then
            present[kept.id] = true
          end
        end
      end

      -- Current Gen 2 does not splice render-pipeline rows itself. Add only
      -- WEATHER there; Gen 1 already has it and must not receive a duplicate.
      if not HostRuntime.isGen2() or present[OUR_ID] then return filtered end

      local addRow = nil
      safe(function()
        local Pipelines = require("src.render.Pipelines")
        if Pipelines and type(Pipelines.rows) == "function" then
          for _, row in ipairs(Pipelines.rows(game) or {}) do
            if type(row) == "table" and row.id == OUR_ID then
              addRow = row
              break
            end
          end
        end
      end)
      -- Fallback descriptor if Pipelines is unavailable (UI mod / engine variance).
      if not addRow then
        addRow = { id = OUR_ID, label = "WEATHER", pipeline = "weather" }
      end
      filtered[#filtered + 1] = unifiedWeatherRow(addRow)
      return filtered
    end)

    if ok and type(merged) == "table" then return merged end
    return out
  end)
end

-- ------- events

-- The weather is world state, so it is restored with the world.  `settle`
-- inside restore() snaps the channels to it, which is why loading into a
-- storm shows a storm on the first frame rather than fading one up.
mod.events:on("save.loaded", function() TOD.restore(); State.restore() end)
mod.events:on("save.created", function() TOD.restore(); State.restore() end)
mod.events:on("save.writing", function() TOD.persist(); State.persist() end)

-- Battle.install registered its battle.started weather-seeding handlers before
-- this event. Prime the battle compositor after those handlers have finalized
-- battle.field.weather so the first battle frame inherits the live storm instead
-- of easing up from zero after the overworld renderer has already stood down.
mod.events:on("battle.started", function(ev)
  BattleDraw.begin(ev and ev.battle or nil)
end)

-- A battle ending drops the battle overlay's own little particle field, so
-- the next battle does not open with the last one's rain already halfway
-- down the screen.
mod.events:on("battle.ended", function() BattleDraw.reset() end)


-- Stars/planets when TIME is NITE (or real night), independent of 3D atmos.
local wxCelestialRaster = { canvas=nil, w=0, h=0, ss=nil, disabled=false }

local function wxDiscSupersample()
  if wxCelestialRaster.ss then return wxCelestialRaster.ss end
  local ss=16
  safe(function()
    local C=V.require("Config")
    local cfg=C and C.get and C.get() or nil
    local v=cfg and cfg.celestial and tonumber(cfg.celestial.discSupersample)
    if v then ss=math.floor(v+0.5) end
  end)
  -- 1 is a valid performance escape hatch, but 16 is the shipped default.
  if ss<1 then ss=1 elseif ss>16 then ss=16 end
  wxCelestialRaster.ss=ss
  return ss
end

local function wxDiscCanvas(g,w,h)
  if wxCelestialRaster.disabled or not (g and g.newCanvas) then return nil end
  if wxCelestialRaster.canvas and wxCelestialRaster.w==w and wxCelestialRaster.h==h then
    return wxCelestialRaster.canvas
  end
  local ok,c=safe(g.newCanvas,w,h,{dpiscale=1,format="rgba8"})
  if not (ok and c) then
    wxCelestialRaster.disabled=true
    return nil
  end
  safe(c.setFilter,c,"linear","linear")
  safe(c.setWrap,c,"clamp","clamp")
  if wxCelestialRaster.canvas and wxCelestialRaster.canvas.release then
    safe(wxCelestialRaster.canvas.release,wxCelestialRaster.canvas)
  end
  wxCelestialRaster.canvas,wxCelestialRaster.w,wxCelestialRaster.h=c,w,h
  return c
end

local function wxPaintCelestialDisc(body, edge, cell, w, h)
  if not (body and body.x and body.y and love and love.graphics) then return end
  local g = love.graphics
  cell = math.max(1, tonumber(cell) or 4)
  edge = tonumber(edge) or h
  local moon = body.moon and true or false
  local discAlpha=math.max(0,math.min(1,tonumber(body._wxAlpha) or 1))
  -- Weather/astronomy colour reaches the actual visible discs. This is what
  -- lets fog soften them, dust redden the sun and a lunar eclipse turn the
  -- moon copper instead of leaving a hard-coded white sprite in the sky.
  local bc=type(body._wxColor)=="table" and body._wxColor or nil
  local br,bg,bb
  if bc and type(bc[1])=="number" then br,bg,bb=bc[1],bc[2] or bc[1],bc[3] or bc[1]
  elseif moon then br,bg,bb=1,1,1 else br,bg,bb=.98,.82,.38 end
  local function C(m) return {math.floor(math.max(0,math.min(1,br*m))*255+.5),math.floor(math.max(0,math.min(1,bg*m))*255+.5),math.floor(math.max(0,math.min(1,bb*m))*255+.5)} end
  local shades
  if moon then shades={C(1.0),C(.90),C(.60),C(.78)}
  else shades={C(1.0),C(.90),C(.70),C(.56)} end
  local DISC_FRAC, DISC_MIN = 0.028, 3
  local rCells = math.max(DISC_MIN, math.floor(h * DISC_FRAC / cell + 0.5))
  -- The sunset halo is no longer faked by enlarging the solid sun sprite.
  -- Its world-space optical layers are driven by horizon contact; keeping this
  -- disc radius constant prevents a 360-degree ring from appearing before set.
  -- `body.x/y` remain floating point all the way to final composition. The
  -- body art is rendered into a small 16x local canvas and filtered back to the
  -- scene, so crossing 0.05 or 0.10 of a display pixel changes coverage this
  -- frame instead of waiting until the centre reaches the next integer pixel.
  local bx = tonumber(body.x) or 0
  local by = tonumber(body.y) or 0
  if by < 0 then by = rCells * cell end
  if by > edge * 0.9 then by = edge * 0.85 end
  local craterR = math.max(1, math.floor(rCells / 5))
  local MOON_CRATERS = { {-0.4,-0.2},{0.2,0.45},{0.5,-0.4},{-0.15,0.7},{0.05,0.05} }

  local function pixel(bodyX,bodyY,pixelCell,dx,dy)
    local d = math.sqrt(dx * dx + dy * dy)
    if d > rCells + 0.05 then return end
    local c
    if d <= rCells * 0.45 then
      c = shades[1]
    elseif d <= rCells * 0.85 then
      c = shades[2]
    else
      if ((dx + dy) % 2) ~= 0 then c = shades[4] else c = shades[2] end
    end
    if moon then
      local illum = math.max(0, math.min(1, tonumber(body._wxIllumination) or 1))
      local phase = tonumber(body._wxPhase) or 0.5
      local nx = dx / math.max(1, rCells)
      local ny = dy / math.max(1, rCells)
      local limb = math.sqrt(math.max(0, 1 - ny * ny))
      local term = (1 - 2 * illum) * limb
      local lit = (phase < 0.5 and nx >= term) or (phase >= 0.5 and nx <= -term)
      if not lit then c = { 18, 21, 30 } end
      for _, cr in ipairs(MOON_CRATERS) do
        local cdx = dx - math.floor(cr[1] * rCells + 0.5)
        local cdy = dy - math.floor(cr[2] * rCells + 0.5)
        if cdx * cdx + cdy * cdy <= craterR * craterR then c = shades[3] end
      end
    end
    local keep = d <= rCells - 0.85 or ((dx * 3 + dy * 5) % 4) ~= 0
    local altDeg=tonumber(body._wxAltitudeDeg)
    if keep and altDeg then
      local radiusDeg=moon and 3.0 or 4.5
      local pixelAlt=altDeg + (-dy/math.max(1,rCells))*radiusDeg
      if pixelAlt < 0 then keep=false end
    end
    if not keep then return end
    local a=discAlpha
    if moon then
      local illum=math.max(0,math.min(1,tonumber(body._wxIllumination) or 1))
      local phase=tonumber(body._wxPhase) or .5
      local nx=dx/math.max(1,rCells); local ny=dy/math.max(1,rCells)
      local limb=math.sqrt(math.max(0,1-ny*ny)); local term=(1-2*illum)*limb
      local lit=(phase<.5 and nx>=term) or (phase>=.5 and nx<=-term)
      if not lit then
        local e=math.max(0,math.min(1,tonumber(body._wxSolarEclipse) or 0))
        -- Near-invisible earthshine avoids the old-full-moon-under-new-phase
        -- look; a real solar eclipse still restores an opaque lunar silhouette.
        a=discAlpha*(.018+.922*e)
      end
    end
    safe(g.setColor, c[1]/255, c[2]/255, c[3]/255, a)
    safe(g.rectangle, "fill", bodyX + dx * pixelCell - pixelCell/2,
          bodyY + dy * pixelCell - pixelCell/2, pixelCell, pixelCell)
  end

  local ss=wxDiscSupersample()
  local padCells=2
  local logicalSize=math.ceil((rCells*2+1+padCells*2)*cell)
  local rw,rh=logicalSize*ss,logicalSize*ss
  local layer=(ss>1) and wxDiscCanvas(g,rw,rh) or nil

  local sx,sy,sw,sh
  local prevCanvas,prevBlendA,prevBlendB
  safe(function()
    if g.getScissor then sx,sy,sw,sh=g.getScissor() end
    if g.getCanvas then prevCanvas=g.getCanvas() end
    if g.getBlendMode then prevBlendA,prevBlendB=g.getBlendMode() end
  end)

  if layer then
    local pushed=false
    safe(function() g.push("all"); pushed=true end)
    safe(g.origin)
    safe(g.setCanvas,layer)
    safe(g.setScissor)
    safe(g.clear,0,0,0,0)
    safe(g.setBlendMode,"alpha","alphamultiply")
    local cx,cy=rw*0.5,rh*0.5
    local scell=cell*ss
    for dy=-rCells,rCells do
      for dx=-rCells,rCells do pixel(cx,cy,scell,dx,dy) end
    end
    if prevCanvas then safe(g.setCanvas,prevCanvas) else safe(g.setCanvas) end
    if g.setScissor then safe(g.setScissor,0,0,math.ceil(w),math.floor(edge)) end
    -- Canvas colour is already alpha-composited; premultiplied composition
    -- preserves the fractional edge coverage created by the 16x downsample.
    safe(g.setBlendMode,"alpha","premultiplied")
    safe(g.setColor,1,1,1,1)
    local inv=1/ss
    safe(g.draw,layer,bx-rw*0.5*inv,by-rh*0.5*inv,0,inv,inv)
    if pushed then safe(g.pop) end
  else
    -- Driver-safe fallback: still uses the floating centre, but cannot create
    -- the extra sample grid. This preserves old compatibility instead of
    -- disabling the sun/moon on canvas-constrained hosts.
    if g.setScissor then safe(g.setScissor,0,0,math.ceil(w),math.floor(edge)) end
    safe(g.setBlendMode,"alpha","alphamultiply")
    for dy=-rCells,rCells do
      for dx=-rCells,rCells do pixel(bx,by,cell,dx,dy) end
    end
  end

  safe(g.setColor,1,1,1,1)
  safe(function()
    if g.setScissor then
      if sx then g.setScissor(sx,sy,sw,sh) else g.setScissor() end
    end
    if prevBlendA then g.setBlendMode(prevBlendA,prevBlendB) end
  end)
end

local function installNightSkyWrap()
  local okLib,hostLib=safe(function() return (Interop and Interop.hostLib and Interop.hostLib()) or nil end)
  if not okLib or not hostLib or type(hostLib.require)~="function" then return end
  local okSky,Sky=safe(function() return hostLib.require("Sky") end)
  if not (okSky and Sky and type(Sky.paint)=="function") or Sky._wxNightWrapped then return end
  local NightSky; safe(function() NightSky=V.require("NightSky") end); if not NightSky then return end
  NightSky._TOD=TOD
  local orig=Sky.paint
  function Sky.paint(w,h,sky,horizonY,cell,body,...)
    local CR2,Atmosphere
    safe(function() CR2=V.require("CelestialRenderer2") end)
    safe(function() Atmosphere=V.require("AtmosphereModel") end)
    local st=CR2 and CR2.state and CR2.state() or nil
    local skyArg=sky
    if sky and type(sky)=="table" and sky.bands and CR2 and CR2.applySkyBands then
      local copy={}; for k,v in pairs(sky) do copy[k]=v end
      local ok,bands=safe(CR2.applySkyBands,sky.bands,Atmosphere); if ok and bands then copy.bands=bands end
      skyArg=copy
    end
    local edge; safe(function() edge=Sky.region(h,horizonY) end); edge=edge or h*.42
    local worldCelestial=false
    safe(function()
      local DA=V.require("DramalessAtmos")
      worldCelestial=DA and DA.handlesCelestialWorld and DA.handlesCelestialWorld() or false
    end)
    local sunBody,moonBody
    -- CelestialRenderer2.projectBodies is the single-owner facade around the
    -- proven CB.projectBoth(w,h,edge,nil,nil) composed/smoothed body path.
    if not worldCelestial and CR2 and CR2.projectBodies then
      safe(function() sunBody,moonBody=CR2.projectBodies(w,h,edge) end)
    end
    local wxNight=st and st.starVisibility and st.starVisibility>.5 or (TOD and TOD.isNight and TOD.isNight())
    safe(function() package.loaded._WX_NIGHT=wxNight and true or false end)
    -- Host gets no legacy body: Weather FX draws both bodies itself so lunar
    -- phase/eclipses and host-independent orientation remain authoritative.
    local okPaint,result=safe(orig,w,h,skyArg,horizonY,cell,nil,...)
    if not okPaint then result=false end
    -- The voxel hosts intentionally posterise the sky into a small number of
    -- checker-dithered horizontal palette bands. Weather FX keeps those live
    -- colours, but repaints the background as one continuous interpolated
    -- gradient so noon/twilight/storm skies read as clear atmosphere rather
    -- than visible stripes. This is an in-memory presentation overlay only;
    -- host files and host sky ownership remain untouched.
    safe(function()
      local SmoothSky=V.require("SmoothSky")
      if SmoothSky and SmoothSky.draw and SmoothSky.draw(w,h,skyArg,edge) then
        result=true
      end
    end)
    local vis=0; safe(function() vis=NightSky.computeNightVisibility and NightSky.computeNightVisibility() or 0; if NightSky.update then NightSky.update(0) end end)
    -- In an active 3D voxel scene, stars/planets/sun/moon are rendered once in
    -- world space through Voxel3D.vp. Do not paint this 2D Sky.region copy: its
    -- `edge` changes with camera pitch, which vertically squashes the celestial
    -- field looking down and stretches it looking up.
    if not worldCelestial then
      if vis>.01 then safe(NightSky.draw,w,h,edge,nil,State.elapsed or 0) end
      if sunBody then
        local ok,drew=safe(NightSky.draw2DCelestialBody,sunBody,"sun",w,h,edge,cell or 4)
        if not (ok and drew) then safe(wxPaintCelestialDisc,sunBody,edge,cell or 4,w,h) end
      end
      if moonBody then
        local ok,drew=safe(NightSky.draw2DCelestialBody,moonBody,"moon",w,h,edge,cell or 4)
        if not (ok and drew) then safe(wxPaintCelestialDisc,moonBody,edge,cell or 4,w,h) end
      end
    end
    return result
  end
  Sky._wxNightWrapped=true
end

mod.events:on("game.ready", function()
  State.settle()

  safe(installNightSkyWrap)
  -- Installed once the game is up, so requiring BattleState cannot race
  -- the engine's own load order.  ALWAYS installed, not only when the row
  -- already reads BEHIND: the wrapper asks on every draw, so installing it
  -- unconditionally is what makes the row take effect immediately instead
  -- of at the next restart.
  safe(function() if Compat and Compat.refresh then Compat.refresh() end end)
  BattleField.install()
  -- Gen 2 only, and only when the pokegear_cards library is there.  It
  -- answers false and logs a reason on every other path.
  safe(function() Pokegear.install() end)
  -- Optional 3D tornado pickup uses the documented movement-collision hook to
  -- freeze new steps only while the presentation-only orbit/lift is active.
  safe(function() if Tornado and Tornado.installHooks then Tornado.installHooks() end end)
  safe(function() if WindPlayer and WindPlayer.installHooks then WindPlayer.installHooks() end end)
  safe(function() if ConnectedWater and ConnectedWater.installHooks then ConnectedWater.installHooks() end end)
  if Settings.debugRain(Config) then
    mod.log:warn("debugRain is ON: heavy rain everywhere, indoors and out, "
      .. "overriding the OPTIONS row. Set debugRain = false in config.lua "
      .. "when you are done testing.")
  end
  mod.log:info("weather_fx %s: %d types, %d channels, clock=%s, battle=%s, with %s",
    mod.exports.version, #Types.list, #Types.channels,
    Config.get().time.source,
    Scene.battleFullScreen() and "screen" or "canvas",
    Interop.describe())
  if #Config.problems > 0 then
    mod.log:warn("config.lua had %d problem(s): %s",
      #Config.problems, table.concat(Config.problems, "; "))
  end
end)

-- ------- developer console
--
-- `weather` in the console (backtick, developer mode) sets the sky without
-- walking the OPTIONS ladder thirteen rungs.  Costs nothing when the
-- console is never opened, and is the fastest way to check a config change.

if mod.commands and type(mod.commands.register) == "function" then
mod.commands:register("weather", function(args)
  local id = args and args[1] and tostring(args[1]):upper()
  if id == "BENCHMARK" or id == "BENCH" then
    local action = args and args[2] and tostring(args[2]):lower() or "full"
    if action == "status" then return Benchmark.status() end
    if action == "stop" then local _,msg=Benchmark.stop(); return msg end
    if action == "last" then return Benchmark.summary() end
    if action == "help" then return "weather benchmark [quick|full|status|stop|last]" end
    local ok,msg=Benchmark.start(action)
    return msg
  end
  if not id or id == "LIST" then
    return "weather ids: " .. table.concat(Types.ids(), " ")
  end
  if id == "RETURN" then
    -- The undo for the one feature that moves you.  Deliberately a
    -- command rather than a menu row: it is a repair, not a setting.
    local mapId = Tornado.origin()
    if not mapId then return "no tornado has carried you anywhere yet" end
    if Tornado.carry(mapId) then return "returned to " .. tostring(mapId) end
    return "could not return you to " .. tostring(mapId)
  end
  if id == "STATUS" then
    return ("%s | %s | battle=%s"):format(
      State.describe(), TOD.describe(), Battle.describe())
  end
  if not Types.byId[id] then
    return ("unknown weather %q -- try `weather list`"):format(id)
  end
  State.set(id, true)
  return "weather set to " .. id
end)
else
  safe(function() mod.log:warn("mod.commands missing; console weather command skipped") end)
end

-- ------- exports
--
-- Published so a companion mod (NPC umbrellas, puddles on the ground
-- plane, a weather readout on the town map) can ask what the weather is
-- without patching this one.  `weather`, `channel`, `battleWeather` and
-- `timeOfDay` are the stable surface; `lib` is everything and carries no
-- promise.

-- Read from the manifest rather than typed here: a hardcoded copy sat at
-- "2.0.0" for twenty releases, so any companion mod checking this mod's
-- version was told the wrong one.  One source of truth, and it is the file
-- the loader already validated.
mod.exports.version = (mod.manifest and mod.manifest.version) or "unknown"
mod.exports.weather = function() return State.id end
mod.exports.channel = function(key) return State.channel(key) end
mod.exports.battleWeather = function() return Types.battleWeather(State.id) end
mod.exports.compat = function()
  if Compat and Compat.describe then return Compat.describe() end
  return "compat: unavailable"
end
mod.exports.timeOfDay = function() return TOD.tod, TOD.hour end
mod.exports.types = function() return Types.list end
mod.exports.benchmark = function() return Benchmark.last() end
-- Weather FX 6 environmental API. These are read-only snapshots/subscriptions;
-- companion mods can react to microclimates and surface conditions without
-- Weather FX patching their code or owning their NPC/gameplay state.
mod.exports.environment = function(x,z)
  local M=V.require("Microclimate"); local S=V.require("EnvironmentSurface"); local H=V.require("HostAdapter")
  if x==nil or z==nil then x,z=H.worldPosition() end
  return { climate=M.sample(), surface=S.sample(x,z), x=x, z=z }
end
mod.exports.performance = function() return V.require("PerformanceGovernor").sample() end
mod.exports.environmentEvents = function(since) return V.require("EnvironmentalEvents").recent(since or 0,{}) end
mod.exports.onEnvironmentEvent = function(kind,fn) return V.require("EnvironmentalEvents").subscribe(kind,fn) end
mod.exports.environmentBehavior = function(kind,climate,surface,extra)
  local B=V.require("EnvironmentBehavior"); if tostring(kind):upper()=="NPC" then return B.npc(climate or V.require("Microclimate").sample(),surface or {}) end
  return B.pokemon(kind,climate or V.require("Microclimate").sample(),extra or {})
end
mod.exports.engineHealth = function()
  local R=V.require("EngineRuntime"); return V.require("EngineHealth").sample(R.stats())
end
-- Weather FX 7 public environmental SDK. Read-only by default: companion mods
-- query state/forecast/events without Weather FX modifying their files/entities.
mod.exports.environmentSDK = V.require("EnvironmentSDK")
mod.exports.environmentSnapshot = function(x,z) return V.require("EnvironmentSDK").snapshot(x,z) end
mod.exports.weatherWorldInteraction = function() return V.require("WeatherWorldInteraction").sample() end
mod.exports.weatherForecast = function(x,z,seconds) return V.require("ForecastEngine").at(x,z,seconds) end
mod.exports.weatherForecastTimeline = function(x,z,steps,stepSeconds) return V.require("ForecastEngine").timeline(x,z,steps,stepSeconds) end
mod.exports.worldClimate = function(x,z) return V.require("WorldClimate").sampleAt(x,z) end
mod.exports.mesoscaleWeather = function(x,z) local M=V.require("MesoscaleField"); if x==nil or z==nil then return M.peek() end; return M.sampleAt(x,z) end
mod.exports.distantWeather = function() return V.require("DistantWeather").sample() end
mod.exports.connectedWater = function() return V.require("ConnectedWater").sample() end
mod.exports.severeWeather = function() return V.require("SevereWeather").sample() end
mod.exports.environmentLighting = function() return V.require("DynamicLighting").sample() end
mod.exports.accumulationGeometry = function() return V.require("AccumulationGeometry").sample() end
mod.exports.terrainPhysics = function(x,z) local H=V.require("HostAdapter"); if x==nil then x,z=H.worldPosition() end; return V.require("TerrainPhysics").at(x,z) end
mod.exports.environmentSave = function() return V.require("EnvironmentPersistence").snapshot() end
mod.exports.environmentRestore = function(data) return V.require("EnvironmentPersistence").restore(data) end
mod.exports.environmentPlugins = V.require("WeatherPluginRegistry")
mod.exports.environmentStreamer = function() return V.require("WorldStreamer").sample() end
mod.exports.gpuWeather = function() return V.require("GPUWeatherEngine").sample() end
mod.exports.volumetricRenderer = function() return V.require("VolumetricRenderer").sample() end
mod.exports.unifiedLighting = function() return V.require("UnifiedLighting").sample() end
mod.exports.environmentLightProbe = function(x,z) local H=V.require("HostAdapter"); if x==nil then x,z=H.worldPosition() end; return V.require("LightProbeGrid").sampleAt(x,z) end
mod.exports.surfaceVisuals = function() return V.require("SurfaceVisuals").sample() end
mod.exports.systemProfiler = function() return V.require("SystemProfiler").sample() end
mod.exports.workloadRouter = function() return V.require("WorkloadRouter").sample() end
-- Read-only preview for a companion mod's own encounter/route display --
-- see lib/Encounters.lua's "LIVE REPORTING" section for exactly what
-- this does and does not guarantee. Never touches, and is never touched
-- by, the real encounter.roll hook above.
mod.exports.encounterOverlay = function(mapId) return Encounters.currentOverlay(mapId) end
mod.exports.weatherEncounters = mod.exports.encounterOverlay
mod.exports.lib = V
