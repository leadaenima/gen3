-- WHAT THE FRAME IS SHOWING.
--
-- The present stage is handed almost nothing -- `{ width, height, scale,
-- dpi }` and a canvas -- and does not say whether the thing under that
-- canvas is the overworld, a battle, or the PC's item screen.  Weather
-- over a full-screen menu would be a bug in every graphics mode, so this
-- module answers the questions the draw path needs, once per frame, from
-- the live game.
--
--   visible     "world" | "battle" | "hidden"
--   outdoor     whether the map the player is standing on has a sky
--   camera      world-pixel scroll, so ground splashes stay on the ground
--   textBox     the rect of an open dialog box, or nil
--
-- THE STACK WALK is the whole trick, and it is four lines: from the top of
-- the state stack downward, the first state that is a battle means battle,
-- the first that is the overworld means world, and the first that is
-- opaque before either means the world is covered and nothing should draw.
-- Transparent overlays -- a text box, a "?" bubble, a quantity box -- are
-- stepped through, which is why weather keeps falling during dialogue.
--
-- That walk gets one behaviour for free that would otherwise need a
-- special case: Dramatic Shape's overworld battles set
-- `BattleState.isOpaque = self:bgMode() ~= "world"`, so a 3D battle fought
-- on the map is a NON-opaque battle with the world live behind it.  The
-- walk reports "battle" with the overworld still resolvable underneath,
-- and `drawScale` uses the opacity to decide whether the world behind
-- needs weather (it does) or whether the battle canvas has it already
-- (lib/BattleDraw.lua, through the battle.overlay hook).
--
-- THE TEXT BOX IS TRACKED so precipitation can be kept off it on the flat
-- renderer.  With a world pipeline running, weather composites under the
-- UI and the question does not arise; without one, `present` is the only
-- stage there is and it lands over everything.  Knowing where the box is
-- turns that from a limitation into a clip.
--
-- PERMISSIONS.  This is what `engine_internals` in the manifest buys, and
-- all it buys: four read-only requires and no writes.  `mod.world` would
-- give the overworld without the permission but not the stack top, and
-- UI compatibility: full-screen menus (any UI mod) set visible=hidden so we
-- draw nothing — we never hook dialogue/party/bag/HUD.
-- "is a menu covering the world" is the question that keeps rain off the
-- item screen.  Every require is pcall'd, so a headless run reports
-- "hidden" and the mod draws nothing rather than throwing inside a render
-- callback.

local V = ...
local mod = V.mod
local Config = V.require("Config")
local Interop = V.require("Interop")

local Scene = {}

local function tryRequire(path)
  local ok, module = pcall(require, path)
  if ok then return module end
  return nil
end

-- Guaranteed table so callers never index nil.
function Scene.ensure()
  if type(Scene.now) ~= "table" then
    Scene.now = {
      visible = "hidden", outdoor = false, mapId = nil, environment = nil,
      isTown = false, camX = 0, camY = 0, indoors = false, owKnown = false,
      playerWorldX = nil, playerWorldY = nil, playerPosKnown = false, pauseMenu = false,
    }
  end
  return Scene.now
end

Scene.now = {
  visible = "hidden", outdoor = false, mapId = nil, environment = nil, isTown = false,
  camX = 0, camY = 0, indoors = false, owKnown = false,
  playerWorldX = nil, playerWorldY = nil, playerPosKnown = false,
  battleOpaque = true, textBox = nil, tod = nil, pauseMenu = false,
}

-- The playfield rect inside the window, captured from the render.hud hook.
-- present's ctx has no letterbox metrics, and reconstructing them means
-- duplicating Renderer:fitScale, uiSize and the survey-zoom UI scale --
-- three engine details that would rot.  The hook is handed the finished
-- viewport, so it is copied.  One frame stale by construction, which
-- matters only on the frame a window is resized.
Scene.viewport = nil

function Scene.setViewport(vp)
  if type(vp) ~= "table" then return end
  local w, h = tonumber(vp.gameWidth), tonumber(vp.gameHeight)
  if not (w and h and w > 0 and h > 0) then return end
  Scene.viewport = {
    x = tonumber(vp.gameX) or 0, y = tonumber(vp.gameY) or 0,
    w = w, h = h,
    -- `scale` is Sp: framebuffer PIXELS per GB pixel.  The present canvas
    -- is in UNITS, so it is the wrong number there by the DPI factor --
    -- which is 1 on a desktop and very much not 1 on a handheld.  Both are
    -- kept; Draw derives what it needs from the rect instead (see below).
    scale = tonumber(vp.scale) or 1,
    dpiX = tonumber(vp.dpiX) or 1, dpiY = tonumber(vp.dpiY) or 1,
    windowW = tonumber(vp.width) or w, windowH = tonumber(vp.height) or h,
  }
end

local function isBattle(state, BattleState)
  if not BattleState then return false end
  return getmetatable(state) == BattleState
end

-- Pause/start-menu screens are a special kind of overlay: the world remains
-- visibly present behind them, so 2D Weather FX must keep rendering.  Screen
-- ids are stamped by Gen1Recomp's Screens.build(), which makes this robust
-- across Gen 1, Gen 2 and UI replacements that preserve the engine screen id.
local PAUSE_SCREEN_IDS = {
  StartMenu=true, Gen2StartMenu=true,
  PokedexMenu=true, Gen2PokedexMenu=true,
  PartyMenu=true, Gen2PartyMenu=true,
  BagMenu=true, Gen2PackMenu=true,
  TrainerCard=true, Gen2TrainerCard=true,
  SummaryMenu=true, Gen2SummaryMenu=true,
  OptionsMenu=true, Gen2OptionsMenu=true,
  Gen2Pokegear=true, ManagerState=true, BindingsMenu=true,
}

local function isPauseMenuState(state)
  if type(state) ~= "table" then return false end
  if state.isPauseMenu or state.pauseMenu or state.isStartMenu or state.weatherFxPauseMenu then
    return true
  end
  local id=tostring(state.screenId or "")
  if PAUSE_SCREEN_IDS[id] then return true end
  if id:find("WeatherFXSettingsRoot",1,true)==1
      or id:find("WeatherFXSettingsGroup_",1,true)==1 then
    return true
  end
  return false
end

local function isTextBox(state, TextBox)
  if type(state) ~= "table" then return false end
  -- Engine dialog boxes
  if TextBox and getmetatable(state) == TextBox then return true end
  -- Area-name / route / town banner mods often use one of these markers
  if state.isTextBox or state.isBanner or state.isAreaName or state.isLocationBanner then
    return true
  end
  local kind = state.kind or state.type or state.class
  if kind == "textbox" or kind == "textBox" or kind == "banner"
      or kind == "area" or kind == "areaName" or kind == "location" then
    return true
  end
  -- Layout fields used by Gen1 text boxes / many banner UIs
  if type(state.boxTy) == "number" and type(state.boxTh) == "number" then
    return true
  end
  return false
end


-- Authoritative 2D movement source for world-wrapped haze.
--
-- Camera translation is NOT movement authority: during map/loading stalls some
-- hosts can keep nudging the camera from held directional input even though the
-- player cannot actually advance. Using that camera directly makes world haze
-- look as if the player is walking during a load. Prefer continuous player px/py
-- when a host exposes it; otherwise Gen1/Gen2 cellX/cellY are converted to the
-- same 16-world-pixel units used by the flat camera.
local function playerWorldPosition(ow)
  local p = ow and (ow.player or ow.hero or ow.avatar)
  if type(p) ~= "table" then return nil, nil end
  local px, py = tonumber(p.px), tonumber(p.py)
  if px and py then return px, py end
  local cx = tonumber(p.cellX or p.tileX or p.tx)
  local cy = tonumber(p.cellY or p.tileY or p.ty)
  if cx and cy then return cx * 16, cy * 16 end
  return nil, nil
end

-- Per-map anchor translating actual player displacement into the coordinate
-- space the haze field already uses. Raw camera movement after the anchor is
-- established is deliberately ignored. That is the loading/input guard.
local hazeMotion = { valid=false, mapId=nil, basePX=0, basePY=0, baseCamX=0, baseCamY=0, lastX=0, lastY=0 }

function Scene.hazeCamera()
  local now = Scene.now or {}
  local rawX, rawY = tonumber(now.camX) or 0, tonumber(now.camY) or 0
  local px, py = tonumber(now.playerWorldX), tonumber(now.playerWorldY)
  local known = now.playerPosKnown and px and py
  if known then
    local mapId = now.mapId
    if (not hazeMotion.valid) or hazeMotion.mapId ~= mapId then
      hazeMotion.valid = true
      hazeMotion.mapId = mapId
      hazeMotion.basePX, hazeMotion.basePY = px, py
      hazeMotion.baseCamX, hazeMotion.baseCamY = rawX, rawY
      hazeMotion.lastX, hazeMotion.lastY = rawX, rawY
    else
      local dx, dy = px - hazeMotion.basePX, py - hazeMotion.basePY
      -- Same-map teleports/warps are not walking. Re-anchor rather than sweeping
      -- the entire haze field across the screen during the transfer.
      if math.abs(dx) > 96 or math.abs(dy) > 96 then
        hazeMotion.basePX, hazeMotion.basePY = px, py
        hazeMotion.baseCamX, hazeMotion.baseCamY = rawX, rawY
        hazeMotion.lastX, hazeMotion.lastY = rawX, rawY
      else
        hazeMotion.lastX = hazeMotion.baseCamX + dx
        hazeMotion.lastY = hazeMotion.baseCamY + dy
      end
    end
    return hazeMotion.lastX, hazeMotion.lastY, true
  end
  -- During a load/unsampleable world, HOLD the last actual-player-derived
  -- parallax coordinate. Weather time continues elsewhere, so wind/meander keeps
  -- moving; only player-command/camera contribution is frozen.
  if hazeMotion.valid then return hazeMotion.lastX, hazeMotion.lastY, false end
  -- Compatibility fallback for an unusual host that exposes no player position.
  return rawX, rawY, false
end

function Scene.resetHazeCamera()
  hazeMotion.valid, hazeMotion.mapId = false, nil
end

-- The live overworld anywhere in the stack, battle or menu on top or not.
-- The same scan mod.world:overworld() does, for the same reason:
-- Game.overworld is the fast path but the stack is the authority.
-- THE GOLD BUG THIS FIXES: nothing drew on a Gold boot -- weather changed,
-- battle effects applied, the OPTIONS row worked, and the screen stayed
-- empty. The cause was here. The stack scan below looks for `isOverworld`,
-- a marker only Gen 1's OverworldState carries
-- (src/world/OverworldController.lua:31); Gold's world
-- (src/world/gen2/World.lua) does not set it, and the `Game.overworld`
-- fallback demands the same marker. So on Gold this answered nil, Scene.now
-- stayed "hidden", and every draw path concluded there was nothing to draw
-- over. Only drawing asked the question, which is why everything else
-- looked fine.
--
-- `mod.world:overworld()` is the engine's own answer to "where is the live
-- world", it is `backed` on both generations in the Gen 2 adapter's coverage
-- table, and each arm resolves it the way its own engine stores the world --
-- Gen 1 by the same stack scan, Gold by `game.world`. Asking it first means
-- this file no longer has to know how either engine keeps its world.
--
-- The scan is kept as a fallback rather than deleted: it is what answers if
-- `mod.world` is ever unavailable (it is built by the loader, so a very
-- early call can precede it), and on Gen 1 it returns the identical object.
local function overworld(Game)
  -- Resolve the engine module at CALL time. On a Gold boot the loader swaps
  -- this require to the Gen-2 proxy; capturing it when Scene.lua loads can
  -- permanently bind the Gen-1 table instead.
  Game = Game or tryRequire("src.core.Game")
  local ok, ow = pcall(function()
    local world = V.mod and V.mod.world
    return world and world:overworld() or nil
  end)
  if ok and type(ow) == "table" and ow.map then return ow end

  local stack = Game and Game.stack
  local states = stack and stack.states
  if type(states) == "table" then
    for i = #states, 1, -1 do
      local s = states[i]
      if type(s) == "table" and s.isOverworld then return s end
    end
  end
  local gow = Game and Game.overworld
  if type(gow) == "table" and gow.isOverworld and gow.map then return gow end
  return nil
end

-- Public for features that need the live world (notably Tornado). Keeping
-- this as a function rather than exporting a captured object preserves the
-- Gen-1/Gen-2 call-time dispatch above.
function Scene.overworld()
  return overworld()
end


-- Walks once and answers three things, because walking three times to
-- answer them separately would be three times the work for a frame that
-- has a fixed budget.
local function inspect(now, Game, BattleState, TextBox)
  now.visible = "hidden"
  now.battleOpaque = true
  now.textBox = nil
  now.uiOverlay = false
  now.pauseMenu = false
  local stack = Game and Game.stack
  local states = stack and stack.states
  local scanned = (type(states) == "table")

  -- Look ahead for a pause-menu anchor before applying the usual fail-closed
  -- unknown-UI rule.  Gen 1's SAVE flow, for example, can put an anonymous
  -- panel/text box above StartMenu.  Once a real pause screen is present, those
  -- helper states are part of the pause stack and must not make 2D weather
  -- vanish.  Unknown UI with no pause anchor still suppresses weather.
  local pauseAnchor = false
  if scanned then
    for i=#states,1,-1 do
      local s=states[i]
      if type(s)=="table" then
        if isBattle(s,BattleState) or s.isOverworld then break end
        if isPauseMenuState(s) then pauseAnchor=true; break end
      end
    end
  end

  for i = scanned and #states or 0, 1, -1 do
    local s = states[i]
    if type(s) == "table" then
      if isTextBox(s, TextBox) then
        now.uiOverlay = true
        if not now.textBox then
          local ty = tonumber(s.boxTy) or 12
          local th = tonumber(s.boxTh) or 6
          now.textBox = { x = 0, y = ty * 8, w = 160, h = th * 8 }
        end
      elseif isBattle(s, BattleState) then
        now.visible = "battle"
        now.battleOpaque = (s.isOpaque ~= false)
        return
      elseif s.isOverworld then
        now.visible = "world"
        now.pauseMenu = pauseAnchor
        return
      elseif isPauseMenuState(s) then
        pauseAnchor = true
        now.pauseMenu = true
        now.uiOverlay = true
      elseif pauseAnchor then
        -- Auxiliary state belonging to an already-identified pause stack.
        now.uiOverlay = true
        now.pauseMenu = true
      else
        -- Every other unknown UI remains fail-closed so Weather FX cannot
        -- paint over arbitrary full-screen menus or mod UIs.
        now.visible = "hidden"
        now.uiOverlay = true
        return
      end
    end
  end

  -- Gen 2's live world does not carry Gen 1's isOverworld marker.  If no
  -- covering non-pause UI was found, ask the engine's world adapter.
  local ok, ow = pcall(overworld, Game)
  if ok and type(ow) == "table" and ow.map then
    now.visible = "world"
    now.pauseMenu = pauseAnchor
  end
end

-- Presentation clock used only for visible weather animation.  Weather
-- simulation keeps real time while PAUSE MENU WEATHER=FROZEN; only the visual
-- clock stops, then continues from the same phase when gameplay resumes.
Scene._weatherAnimTime=nil
function Scene.updateWeatherAnimationClock(dt, paused, seed)
  if Scene._weatherAnimTime==nil then
    Scene._weatherAnimTime=tonumber(seed) or 0
  end
  local step=math.max(0,tonumber(dt) or 0)
  if not paused then Scene._weatherAnimTime=Scene._weatherAnimTime+step end
  Scene.animationPaused=paused and true or false
  return Scene._weatherAnimTime
end

function Scene.weatherAnimationTime(fallback)
  if Scene._weatherAnimTime==nil then return tonumber(fallback) or 0 end
  return Scene._weatherAnimTime
end

function Scene.resetWeatherAnimationClock(seed)
  Scene._weatherAnimTime=tonumber(seed)
  Scene.animationPaused=false
end


-- Towns keep brighter night lighting; routes/wilderness go darker.
local function isTownMap(ow, mapId)
  local map = ow and ow.map
  local def = type(map) == "table" and (map.def or map) or nil
  if type(def) == "table" then
    local env = def.environment
    if type(env) == "string" and env:upper() == "TOWN" then return true end
  end
  local id = tostring(mapId or "")
  if id == "" then return false end
  -- Common id patterns for settlements (Gen 1/2).
  if id:find("TOWN", 1, true) or id:find("CITY", 1, true) then return true end
  if id:find("PALLET", 1, true) or id:find("VIRIDIAN", 1, true)
      or id:find("PEWTER", 1, true) or id:find("CERULEAN", 1, true)
      or id:find("VERMILION", 1, true) or id:find("LAVENDER", 1, true)
      or id:find("CELADON", 1, true) or id:find("FUCHSIA", 1, true)
      or id:find("SAFFRON", 1, true) or id:find("CINNABAR", 1, true)
      or id:find("INDIGO", 1, true) then
    -- Only pure settlement maps: e.g. VIRIDIAN_CITY yes, VIRIDIAN_FOREST no
    if id:find("FOREST", 1, true) or id:find("CAVE", 1, true)
        or id:find("ROUTE", 1, true) or id:find("GYM", 1, true)
        or id:find("MART", 1, true) or id:find("CENTER", 1, true)
        or id:find("HOUSE", 1, true) then
      return false
    end
    if id:find("CITY", 1, true) or id:find("TOWN", 1, true) then return true end
  end
  -- Gen 2 settlements
  if id:find("CHERRYGROVE", 1, true) or id:find("VIOLET", 1, true)
      or id:find("AZALEA", 1, true) or id:find("GOLDENROD", 1, true)
      or id:find("ECRUTEAK", 1, true) or id:find("OLIVINE", 1, true)
      or id:find("CIANWOOD", 1, true) or id:find("MAHOGANY", 1, true)
      or id:find("BLACKTHORN", 1, true) or id:find("NEW_BARK", 1, true) then
    if id:find("CITY", 1, true) or id:find("TOWN", 1, true) or id:find("NEW_BARK", 1, true) then
      return true
    end
  end
  return false
end

function Scene.isTown()
  return Scene.now.isTown and true or false
end

-- HAS THIS MAP GOT A SKY?
--
-- `Map.isOutdoor(def)` and nothing else: `def.outdoor` when the map states
-- one, otherwise `tileset == "OVERWORLD"`.
--
-- VERSION 2.3.1 ADDED A SECOND SIGNAL HERE AND IT WAS A BAD MISTAKE, worth
-- recording so it is not reinvented.  The idea was that a cave laid out
-- with outdoor tiles would wrongly pass the tileset test, so a map should
-- also have to BE the engine's `lastOutdoor` to count as having a sky.
--
-- Both halves of that were wrong.
--
--  1. `lastOutdoor` is not "the outdoor map you are on".  The engine sets
--     it on a transition OFF an outdoor map (OverworldController:4013), so
--     it records the outdoor map you last LEFT.  Walk out of a house in
--     Pallet Town and north to Route 1 and it still says PALLET_TOWN --
--     which made every route read as indoors for anyone who had ever
--     entered a building, suppressing all precipitation while leaving fog
--     and the grade drawing.  "Only fog ever appears" was that bug.
--
--  2. The problem it was solving did not exist.  Rock Tunnel, Mt Moon and
--     Victory Road use the CAVERN tileset, so `Map.isOutdoor` already
--     answered false for them.
--
-- The general lesson: a second signal can only be worth adding if its
-- meaning has been READ rather than assumed, and if the thing it fixes has
-- been seen to be broken.  Neither was true here.
--
-- Caves that genuinely do use outdoor tiles can be named in config.lua's
-- `indoorMaps`, which is an explicit list rather than a guess.
-- Maps that must never run outdoor weather (ships, forced interiors).
-- SS Anne decks often use OVERWORLD tilesets so Map.isOutdoor can say true;
-- treat the whole ship like a building/cave.
local function forceIndoorMap(mapId)
  if not mapId then return false end
  local id = tostring(mapId)
  local cfg = Config.get()
  if cfg.indoorMaps and (cfg.indoorMaps[id] or cfg.indoorMaps[id:upper()]) then
    return true
  end
  local u = id:upper():gsub("-", "_"):gsub(" ", "")
  if u:find("SSANNE", 1, true) or u:find("SS_ANNE", 1, true) then return true end
  if u:find("S_S_ANNE", 1, true) or u:find("SSANNE", 1, true) then return true end
  -- Gen1 common ship map prefixes
  if u:find("ANNE", 1, true) and (u:find("CABIN", 1, true) or u:find("BOW", 1, true)
      or u:find("KITCHEN", 1, true) or u:find("CAPTAIN", 1, true)
      or u:find("B1F", 1, true) or u:find("1F", 1, true) or u:find("2F", 1, true)
      or u:find("3F", 1, true)) then
    return true
  end
  return false
end

local function outdoorOf(ow, mapId, Map)
  local def = ow and ow.map and ow.map.def
  if not def then return false end
  if forceIndoorMap(mapId) then return false end
  -- GEN 2 FIRST, because `Map.isOutdoor` cannot answer for it.  That
  -- function is `def.outdoor, else tileset == "OVERWORLD"` -- and a Gen 2
  -- map has neither: it carries `def.environment`, one of ROUTE, TOWN,
  -- INDOOR, CAVE, DUNGEON, GATE.  So every Gen 2 map answered "not
  -- outdoor", the mod believed the player was permanently indoors, and
  -- indoors suppresses all precipitation -- which is exactly why Gold had
  -- a debug readout saying `in` while standing in the middle of
  -- Cherrygrove, and no weather at all.
  --
  -- ROUTE and TOWN are the engine's own outdoor pair: `World.lua:8366`
  -- and the Bike and Dig checks all treat exactly those two as outside.
  local env = def.environment
  if type(env) == "string" then
    return env == "ROUTE" or env == "TOWN"
  end

  Map = Map or tryRequire("src.world.Map")
  if Map and type(Map.isOutdoor) == "function" then
    local ok, out = pcall(Map.isOutdoor, def)
    if ok then return out and true or false end
  end
  if def.outdoor ~= nil then return def.outdoor and true or false end
  return def.tileset == "OVERWORLD"
end

-- Rebuild Scene.now.  Called once per frame from the pipeline's update
-- hook, which the engine runs whatever the level -- so this is guarded to
-- be cheap and total: it never throws, and never allocates beyond the one
-- small table a text box needs.
function Scene.sample()
  local now = Scene.now
  local ok = pcall(function()
    -- Engine modules are intentionally resolved here, once per sample. Never
    -- move these back to file scope: Gold may supply different proxies after
    -- the module itself has already been loaded.
    local Game = tryRequire("src.core.Game")
    local BattleState = tryRequire("src.battle.BattleState")
    local Map = tryRequire("src.world.Map")
    local TextBox = tryRequire("src.render.TextBox")
    local ow = overworld(Game)
    inspect(now, Game, BattleState, TextBox)
    -- STICKY INDOORS.
    --
    -- `overworld()` can come back nil while the overworld state is not
    -- reachable -- most importantly during a BATTLE, where the battle state is
    -- on top of the stack and the map may not be sampleable. The old line was
    --     now.indoors = (ow ~= nil) and (not now.outdoor)
    -- which makes "I cannot see the map" mean "outdoors". That is fail-OPEN,
    -- and it is the single root cause behind three separate reports:
    --
    --   * weather appearing in battles inside caves, buildings and the SS Anne
    --     -- the battle starts, the overworld goes unsampleable, indoors flips
    --     to false, and the sky is seeded into a fight happening underground;
    --   * WeatherState seeing _wasIndoors go true->false mid-battle, which is
    --     read as "the player just stepped outside" -- it resumes weather and
    --     RESETS the 5-minute indoor timer, so a player who battles inside a
    --     cave never accumulates the stay that is supposed to advance the
    --     queue;
    --   * the converse flapping, which is the likeliest explanation for
    --     weather sometimes not appearing in battles at all.
    --
    -- When the overworld cannot be sampled we now KEEP the last known answer
    -- rather than inventing one. owKnown says which it is, so callers that
    -- genuinely need certainty can tell the difference.
    now.owKnown = (ow ~= nil)
    if ow == nil then
      -- Hold mapId/outdoor/indoors at their last sampled values.
      now.indoors = now.indoors and true or false
    else
      now.mapId = ow.map and ow.map.id or nil
      now.outdoor = outdoorOf(ow, now.mapId, Map)
      now.indoors = not now.outdoor
    end
    local map = ow and ow.map
    local env = map and ((map.def and map.def.environment) or map.environment) or nil
    now.environment = type(env) == "string" and env or nil
    now.isTown = isTownMap(ow, now.mapId) and now.outdoor
    local cam = ow and ow.camera
    now.camX = (cam and tonumber(cam.x)) or 0
    now.camY = (cam and tonumber(cam.y)) or 0
    local pwx, pwy = playerWorldPosition(ow)
    now.playerPosKnown = (pwx ~= nil and pwy ~= nil)
    if now.playerPosKnown then
      now.playerWorldX, now.playerWorldY = pwx, pwy
    end
    now.tod = ow and ow.tod or nil
    local last = ow and ow.lastOutdoor
    now.lastOutdoor = last and last.id or nil
  end)
  if not ok then
    -- Note this deliberately does NOT reset `indoors`/`mapId`. A sampling error
    -- is not evidence that the player walked outside; clearing it here would
    -- reintroduce the fail-open behaviour the sticky logic above exists to stop.
    now.visible = "hidden"
    now.owKnown = false
    now.playerPosKnown = false
    now.outdoor, now.isTown, now.environment = false, false, nil
    now.textBox = nil
  end
  return now
end

-- Where battle weather belongs this session.  `auto` picks `screen` when
-- something is installed that draws a battle wider than the engine's
-- 160x144 canvas -- otherwise the overlay would cover only that classic
-- box sitting inside a much larger scene.
function Scene.battleFullScreen()
  local mode = Config.get().battleView
  if mode == "screen" then return true end
  if mode == "canvas" then return false end
  return (Interop.wideBattle())
end

-- Whether the weather should draw in the WHOLE-FRAME pass this frame, and
-- at what strength.  Returns 0 for "not at all", which every draw system
-- treats as a return.
--
--   * a covered world draws nothing, whatever the weather
--   * a battle whose canvas is opaque draws nothing HERE: the battle
--     overlay hook has already drawn it inside the battle's own 160x144
--     canvas, and doing both would double every particle
--   * a battle you can see the world through (Dramatic Shape's overworld
--     battles) draws at the BATTLES setting, because that world is real
--   * indoors nothing falls; the grade survives if the player asked for it,
--     so a storm still glooms a room with a window in it
function Scene.drawScale(settings)
  local now = Scene.now
  if now.visible == "hidden" then return 0, false end
  local precipitation = true
  local scale = 1
  -- battle.started can precede the Scene stack reporting "battle" by a few
  -- transition frames. Do not let the flat overworld precipitation layer keep
  -- falling over that opening transition; BattleDraw owns the incoming field.
  if now.visible ~= "battle" then
    local okB,B=pcall(V.require,"Battle")
    if okB and B and B.current and B.current() then
      return scale,false
    end
  end
  if now.visible == "battle" then
    -- An opaque battle normally draws nothing HERE: lib/BattleDraw.lua has
    -- already drawn it inside the battle's own 160x144 canvas, and doing
    -- both would double every particle.  In `screen` mode that canvas is
    -- too small to be the whole battle, so this pass takes over and the
    -- overlay stands down instead.
    if now.battleOpaque and not Scene.battleFullScreen() then return 0, false end
    scale = settings.battleScale()
    if scale <= 0 then return 0, false end
    do
      local okA, Battle = pcall(V.require, "Battle")
      if okA and Battle and Battle.animEnabled and not Battle.animEnabled() then return 0, false end
      if okA and Battle and Battle._startedIndoors then return 0, false end
    end
    -- With gen3_battle_ui, weather is drawn only via battle.overlay (canvas).
    -- Skip the whole-frame battle pass to avoid double rain over Gen 3 HUD.
    local hasGen3 = false
    pcall(function()
      if mod and mod.find and mod.find("gen3_battle_ui") then hasGen3 = true end
    end)
    if hasGen3 and not Scene.battleFullScreen() then
      return 0, false
    end
    return scale, true
  end
  if now.indoors then
    -- Never let ordinary precipitation fall indoors. DEBUG RAIN is the one
    -- deliberate testing exception. With INDOORS=TINT, however, keep the
    -- compositor alive with `precipitation=false` so the retained storm
    -- grade and lightning flash can reach the room without spawning drops,
    -- snow, hail, splashes, puddles, fog banks, or debris.
    if settings.debugRain(Config) then return scale, true end
    local indoorMode = "off"
    pcall(function() indoorMode = settings.get("indoors") or "off" end)
    if indoorMode == "tint" then return scale, false end
    return 0, false
  end
  return scale, precipitation
end

return Scene
