-- THE GEN 3 ARM OF THE MOD FACADE.
--
-- A mod asks for the module names the Gen 1 engine publishes -- `src.core.Game`,
-- `src.world.Map` -- because those are the names the mod API documents. On a
-- Gen 2 boot src/mods/Gen2Compat.lua answers them with Gold's equivalents. This
-- file is the same job for Ruby.
--
-- WHY IT HAD TO EXIST AT ALL, and why its absence was worse than an error.
-- The loader's interposition used to read `generation ~= 1`, written when Gen 2
-- was the only other generation. Once Ruby arrived, a Gen 3 mod asking for
-- `src.core.Game` was handed GOLD's adapter and `src.world.Map` was handed
-- `src.world.gen2.Map`. Those are live, working modules -- of a game that is
-- not running. The mod reads an empty world off them and has no way to tell
-- why. An outright "no adapter" is a better answer than a plausible wrong one,
-- and that is the floor this file guarantees even for the names it does not
-- yet cover.
--
-- WHAT IS AND IS NOT HERE. Gen2Compat is two thousand lines because Gold's
-- engine is a full parallel of Gen 1's, module for module. Ruby is not built
-- that way: main.lua branches to src/core/Game3.lua and that ONE object is the
-- overworld, the battle, every menu and the renderer -- "The three never branch
-- into each other", as main.lua puts it. So there is no src/world/gen3/Map.lua
-- to alias, and most of this facade is a translation onto fields of Game3
-- rather than a redirect to a sibling module.
--
-- The coverage table below is the honest statement of how far that goes, in
-- the same three states Gen2Compat uses -- backed / warned / absent -- so the
-- mod manager can show an author what a name will actually do here rather than
-- letting them find out at runtime.

local Logger = require("src.core.Logger")

local Gen3Compat = {}

-- SHARED with Gen2Compat.COVERAGE_VERSION: this numbers the coverage()
-- CONTRACT ({module, kind, target, members, notes}), not this arm's
-- progress. Both arms return the same shape, so they carry the same
-- number; bumping one alone tells a reader the contract moved.
Gen3Compat.COVERAGE_VERSION = 1
Gen3Compat.STATUS = { BACKED = "backed", WARNED = "warned", ABSENT = "absent" }

-- The live game, injected by the loader (Gen3Compat.bind) rather than required:
-- Game3 is an instance, not a singleton module, so there is nothing to require.
local resolveGame = nil

local function live()
  if not resolveGame then return nil end
  local ok, game = pcall(resolveGame)
  if not ok then return nil end
  return game
end

local built = {}
local claimants = {}
local warned = {}

local function warnOnce(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  Logger.warn(fmt, ...)
end

local function words(text)
  local out = {}
  for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
  return out
end

-- ---------------------------------------------------------------- src.core.Game
--
-- A FACADE, never an alias. Gen 1's Game is a module and the live state at
-- once; Ruby's is an instance main.lua holds, so every read has to reach the
-- live one at the moment it is asked, not at the moment this table was built.
-- A mod that captured `Game` at load time and read `.data` a minute later must
-- see the data the game has now.
local function buildGame()
  local proxy = {}

  -- Each entry answers ONE Gen 1 name. Anything absent from here falls through
  -- to nil rather than to a Gen 1 or Gen 2 module, which is the whole point.
  local translate = {}

  -- `.data` is the same idea on both: the merged generated dataset.
  function translate.data(g) return g.data end

  -- Gen 1's `.save` is the save table; Game3 keeps its state on itself and
  -- publishes `save.options` for the shared launcher options file
  -- (Game3:modOptionsStore). Handing back that table is honest -- it IS what
  -- the manager and the options screen read -- but it is not a Gen 1 save
  -- struct, so the coverage table lists `save` as warned rather than backed.
  function translate.save(g)
    if g.modOptionsStore then pcall(g.modOptionsStore, g) end
    return g.save
  end

  function translate.input(g)
    return g.input or require("src.core.Input")
  end

  function translate.options(g) return g.options end

  -- `stack` is the mod manager's real StateStack while that screen is open;
  -- otherwise the standing one from Game3ModWorld, whose top() answers the
  -- overworld in free roam. Mods read stack:top() to decide whether a key is
  -- theirs to take, and nil there reads as "some screen owns the keyboard" --
  -- which is why the free-roam-only hotkeys did nothing before this.
  function translate.stack(g)
    if g.stack then return g.stack end
    if type(g.modStack) ~= "function" then return nil end
    local ok, stack = pcall(g.modStack, g)
    return ok and stack or nil
  end

  function translate.writeOptions(g)
    return function()
      if g.writeOptions then return g:writeOptions() end
    end
  end

  -- `overworld` is the object every renderer mod reaches for, and Ruby has no
  -- OverworldController to hand over -- the map, camera, NPCs and world draw
  -- are fields and methods ON the Game3 instance. src/core/Game3ModWorld.lua
  -- builds the SHAPE a mod expects over those, which is a deliberate choice:
  -- drop-in compatibility is worth more here than making every mod learn a
  -- Ruby-specific route.
  --
  -- What makes that safe rather than the plausible-wrong-answer this file
  -- exists to stop is the rule that view keeps: every field is a live read off
  -- the game, and anything Ruby genuinely lacks is ABSENT rather than filled
  -- in. It is a different shape over real state, not a real shape over
  -- invented state.
  function translate.overworld(g)
    if type(g.modOverworld) ~= "function" then return nil end
    local ok, view = pcall(g.modOverworld, g)
    if not ok then return nil end
    return view
  end

  -- Gen 2 calls the same object `world`; both names resolve here so a mod
  -- written against either engine finds it.
  translate.world = translate.overworld

  -- Thin Renderer seam for DRAMATIC_SHAPE OverworldBattle: Gen 1 stores a
  -- pipeline/battle canvas on Renderer.worldOverride and endFrame blits it
  -- behind the UI. Ruby has no Renderer object; Game3:draw consumes the same
  -- slot (self.worldOverride) via presentWorldCanvas when a battle stages.
  function translate.renderer(g)
    if g._modRenderer then return g._modRenderer end
    local function isCanvas(v)
      if type(v) == "userdata" then
        return type(v.getWidth) == "function" and type(v.getHeight) == "function"
      end
      if type(v) == "table" then
        return type(v.getWidth) == "function" and type(v.getHeight) == "function"
      end
      return false
    end
    local R = {}
    function R:setWorldOverride(canvas)
      if canvas ~= nil and not isCanvas(canvas) then canvas = nil end
      g.worldOverride = canvas
    end
    -- Names OverworldBattle / BattleExit may poll; answer the Gen 1 shape
    -- without claiming a full two-pass Renderer.
    function R:beginFrame() g.worldOverride = nil end
    function R:fitScale()
      if type(g.fitScale) == "function" then
        local ok, s = pcall(g.fitScale, g)
        if ok and type(s) == "number" then return s end
      end
      return 1
    end
    function R:uiSize()
      return 240, 160
    end
    -- free_fly airborne tick calls Game.renderer:worldViewSize() for
    -- camera:follow (colon self). Gen1 Renderer returns world-pass vw,vh;
    -- Ruby has no Renderer — answer a stable viewport so the pcall'd
    -- freeFlyTick does not warn every frame. Prefer live Game3 view size.
    function R:worldViewSize()
      local vw = tonumber(g.viewW)
      local vh = tonumber(g.viewH)
      if vw and vh and vw > 0 and vh > 0 then
        return vw, vh
      end
      local okG, lg = pcall(function()
        return love and love.graphics
      end)
      if okG and lg and type(lg.getDimensions) == "function" then
        local okD, dw, dh = pcall(lg.getDimensions, lg)
        if okD and type(dw) == "number" and type(dh) == "number"
           and dw > 0 and dh > 0 then
          local scale = 1
          if type(g.fitScale) == "function" then
            local okS, s = pcall(g.fitScale, g)
            if okS and type(s) == "number" and s > 0 then scale = s end
          end
          vw = math.ceil(dw / scale)
          vh = math.ceil(dh / scale)
          if vw % 2 ~= 0 then vw = vw + 1 end
          if vh % 2 ~= 0 then vh = vh + 1 end
          return vw, vh
        end
      end
      return 240, 160
    end
    g._modRenderer = R
    return R
  end

  local ABSENT_NOTE = {
  }

  return setmetatable(proxy, {
    __index = function(_, key)
      local g = live()
      if not g then return nil end
      local fn = translate[key]
      if fn then return fn(g) end
      local note = ABSENT_NOTE[key]
      if note then
        warnOnce("game." .. key,
          "src.core.Game.%s has no Gen 3 backing: %s", key, note)
        return nil
      end
      -- everything else reads straight off the live game, which is right for
      -- the many names Game3 shares with Gen 1 by having the same job
      local value = g[key]
      if type(value) == "function" then
        -- BOTH CALL CONVENTIONS, because mods use both. Gen 1's Game is a
        -- module, so `Game.foo(x)` and `Game:foo(x)` are the same call there
        -- and a mod may write either -- DRAMATIC_SHAPE wraps keypressed with
        -- `function Game:keypressed(key)` and reads the old one with
        -- `local inner = Game.keypressed`. Ruby's are instance methods that
        -- need the game as self, so a plain bind makes `Game:foo(x)` pass
        -- self twice and land x in the wrong slot -- silently, since Lua does
        -- not mind an extra argument.
        --
        -- So drop a leading self when it IS this proxy or the game, and
        -- otherwise pass everything through untouched.
        return function(first, ...)
          if first == proxy or first == g then return value(g, ...) end
          return value(g, first, ...)
        end
      end
      return value
    end,
    __newindex = function(_, key, value)
      local g = live()
      if g then g[key] = value end
    end,
  })
end

-- --------------------------------------------------------------- src.world.Map
--
-- A NARROW facade, and narrow because that is all the name means here. Gen 1's
-- Map is a class over a block table; Ruby has metatiles and no block table at
-- all, so there is nothing to alias. What a mod actually reads off the module
-- is `Map.isOutdoor(def)` -- and that question Ruby answers better than Gen 1
-- does: Red infers it from the tileset name, while the GBA cartridge stores a
-- map type per header and Game3.isOutdoorMapType already reads it
-- (MAP_TYPE_TOWN / CITY / ROUTE / UNDERWATER / OCEAN_ROUTE are outside,
-- INDOOR and SECRET_BASE are not).
--
-- Map.new is NOT served. A mod calling it would be constructing a Gen 1 map
-- object, and there is no Gen 3 object for it to come out as.
local function buildMap()
  local Game3 = require("src.core.Game3")
  local Map = {}

  function Map.isOutdoor(def)
    if type(def) ~= "table" then return false end
    -- an explicit flag wins, the way Gen 1's does
    if def.outdoor ~= nil then return def.outdoor end
    return Game3.isOutdoorMapType(def.mapType) == true
  end

  -- Gen 1's wider set (CheckIfInOutsideMap). Ruby's map types already draw
  -- the same line, so the two answers coincide rather than needing a second
  -- tileset list.
  function Map.isOutside(def)
    return Map.isOutdoor(def)
  end

  -- Gen 1 Map.defPassable(def, x, y) reads the block table. Ruby has
  -- metatiles; the closest honest answer is the live Game3:canStep at that
  -- cell when a game is bound, else "unknown → passable" so a wrap that
  -- only gates on false stays open rather than soft-locking the overworld.
  function Map.defPassable(def, x, y)
    local g = live()
    if g and type(g.canStep) == "function" and type(x) == "number" and type(y) == "number" then
      local ok, allowed = pcall(g.canStep, g, x, y)
      if ok then return allowed and true or false end
    end
    return true
  end
  Map.isPassable = Map.defPassable

  -- Live modMapView when a game is bound (preferred path for block/tile).
  local function liveView(def)
    local g = live()
    if not (g and type(g.modMapView) == "function") then return nil, g end
    local map = def
    if type(def) ~= "table" or not def.grid then
      map = g.map
    end
    if not map then return nil, g end
    local ok, view = pcall(g.modMapView, g, map)
    if ok and type(view) == "table" then return view, g end
    return nil, g
  end

  -- Soft block/tile reads: prefer the live metatile view; never throw.
  function Map.blockAt(def, x, y)
    local view = liveView(def)
    if view and type(view.blockAt) == "function" then
      local ok, id = pcall(view.blockAt, view, x, y)
      if ok then return id end
    end
    if type(def) == "table" and type(def.blocks) == "table"
        and type(x) == "number" and type(y) == "number"
        and type(def.width) == "number" then
      local w = def.width
      if x >= 0 and y >= 0 and x < w and y < (def.height or 0) then
        return def.blocks[y * w + x + 1]
      end
      return def.borderBlock
    end
    return 0
  end

  function Map.tileAt(def, x, y)
    -- Gen 1 tileAt is 8px; Ruby metatiles are the collision cell. Answer
    -- the metatile id so a wrap that only compares != nil still runs.
    return Map.blockAt(def, x, y)
  end

  function Map.isWalkableCell(def, x, y)
    local view = liveView(def)
    if view and type(view.isWalkableCell) == "function" then
      local ok, v = pcall(view.isWalkableCell, view, x, y)
      if ok then return v and true or false end
    end
    return Map.defPassable(def, x, y)
  end

  function Map.isWaterCell(def, x, y)
    local view = liveView(def)
    if view and type(view.isWaterCell) == "function" then
      local ok, v = pcall(view.isWaterCell, view, x, y)
      if ok then return v and true or false end
    end
    local g = live()
    if g and type(g.isWaterCell) == "function" then
      local ok, v = pcall(g.isWaterCell, g, x, y)
      if ok then return v and true or false end
    end
    return false
  end

  function Map.inBounds(def, x, y)
    local view = liveView(def)
    if view and type(view.inBounds) == "function" then
      local ok, v = pcall(view.inBounds, view, x, y)
      if ok then return v and true or false end
    end
    if type(def) ~= "table" then return false end
    local w = tonumber(def.width) or tonumber(def.widthCells) or 0
    local h = tonumber(def.height) or tonumber(def.heightCells) or 0
    return type(x) == "number" and type(y) == "number"
      and x >= 0 and y >= 0 and x < w and y < h
  end

  -- Soft setBlock: accept the call so weather_fx / cut-tree wraps do not
  -- throw; Ruby metatile writes go through Game3.noteGridWrite when live.
  function Map.setBlock(def, x, y, block)
    local g = live()
    if g and type(g.setMetatile) == "function" then
      pcall(g.setMetatile, g, x, y, block)
      return
    end
    if type(def) == "table" and type(def.blocks) == "table"
        and type(x) == "number" and type(y) == "number"
        and type(def.width) == "number" then
      local w = def.width
      if x >= 0 and y >= 0 and x < w and y < (def.height or 0) then
        def.blocks[y * w + x + 1] = block
      end
    end
  end

  -- Map.new: prefer the live modMapView (identity-stable, metatile-backed).
  -- Otherwise a soft stub so require+new never hard-fails weather_fx /
  -- overworld_wild_spawns probes. Not a Gen 1 block-table Map.
  function Map.new(def, _tilesetDef)
    local view = liveView(type(def) == "table" and def or nil)
    if view then return view end
    def = type(def) == "table" and def or {}
    local stub = {
      id = def.id,
      generation = 3,
      def = def,
      width = tonumber(def.width) or 0,
      height = tonumber(def.height) or 0,
      widthCells = tonumber(def.widthCells) or tonumber(def.width) or 0,
      heightCells = tonumber(def.heightCells) or tonumber(def.height) or 0,
      blocks = def.blocks or {},
      objects = def.objects or {},
    }
    function stub:blockAt(x, y) return Map.blockAt(self.def, x, y) end
    function stub:tileAt(x, y) return Map.tileAt(self.def, x, y) end
    function stub:isWalkableCell(x, y) return Map.isWalkableCell(self.def, x, y) end
    function stub:isWaterCell(x, y) return Map.isWaterCell(self.def, x, y) end
    function stub:inBounds(x, y) return Map.inBounds(self.def, x, y) end
    function stub:setBlock(x, y, block) return Map.setBlock(self.def, x, y, block) end
    function stub:cellTile(x, y) return self:blockAt(x, y) end
    return stub
  end

  return setmetatable(Map, {
    __index = function(_, key)
      warnOnce("map." .. tostring(key),
        "src.world.Map.%s has no Gen 3 backing: Ruby has metatiles and no "
        .. "Gen 1 block table; soft Map.new / blockAt / passable are the "
        .. "supported subset",
        tostring(key))
      return nil
    end,
  })
end

-- ------------------------------------------------------------ src.render.GBCFX
--
-- The Game Boy Colour filter: a full-screen present pass that exists for Gen 1
-- and Gen 2 and has no meaning on a GBA cartridge at all. Ruby's art is
-- true-colour and is never re-mapped, so there is nothing here to switch on.
--
-- Served anyway, because a require that THROWS is the worst of the three
-- possible answers. DRAMATIC_SHAPE calls exactly one function on it --
-- `GBCFX.setLevel(0)` -- and not to use the effect but to CLEAR it: key 3 is
-- the one that used to turn TILT on and sits beside the one that turned GBC FX
-- on, and the mod takes both keys, so it switches both off on every press to
-- leave a player who had one running a way back. On Ruby that is already true
-- of the world, so the honest implementation is to accept the call and do
-- nothing.
--
-- Every other name in the Gen 2 module is here too, answering the value that
-- means "this effect is not running", because a mod that asks a question
-- should get a truthful answer rather than a nil index. `present` returns its
-- canvas UNCHANGED -- returning nil there would blank the screen.
local function buildGbcFx()
  local GBCFX = {}
  function GBCFX.setLevel() return 0 end
  function GBCFX.cycle() return 0 end
  function GBCFX.applyOptions() end
  function GBCFX.isSupported() return false end
  function GBCFX.active() return false end
  function GBCFX.shader() return nil end
  function GBCFX.levelLabel() return "OFF" end
  function GBCFX.present(canvas) return canvas end
  return setmetatable(GBCFX, {
    __index = function(_, key)
      warnOnce("gbcfx." .. tostring(key),
        "src.render.GBCFX.%s has no Gen 3 backing: the Game Boy Colour "
        .. "filter has no meaning on a GBA cartridge", tostring(key))
      return nil
    end,
  })
end

-- ------------------------------------------------------- src.ui.OptionsMenu
--
-- Gen 1's options screen is a module a mod can PATCH: DRAMATIC_SHAPE wraps
-- `OptionsMenu.update` so that stepping a row which changes the LIST -- the
-- VOXEL ladder crossing FULL, 3D-BTL going on -- rebuilds the rows under the
-- cursor instead of leaving a stale list.
--
-- Ruby's options screen is not that module. It is Game3:optionMenuSpec plus
-- Game3:stepOptionMenu, and it rebuilds its spec from scratch on EVERY draw
-- and every step -- so the staleness the mod's wrapper exists to fix cannot
-- happen here, and a row's label follows its value with nothing patched.
--
-- Served anyway, for the same reason GBCFX is: the require threw, and a mod
-- cannot be expected to guess which engine it is on. The wrapper installs
-- against this, finds an `update` that does nothing and a `new` that answers
-- an empty row list, and its rebuild is a no-op -- while the rows themselves
-- appear on Ruby's own screen, because both engines read them from the same
-- registry (Pipelines.rows and the ui.options.rows hook).
local function buildOptionsMenu()
  local OptionsMenu = {}
  OptionsMenu.__index = OptionsMenu
  -- Marker DRAMATIC_SHAPE stamps after wrapping update. Pre-seeded so the
  -- mod's `if not OptionsMenu.dramaticShapeFullHook` read does not trip the
  -- __index warn ("has no Gen 3 backing") -- the field is real, just false
  -- until the mod claims it. Ruby rebuilds optionMenuSpec every frame, so
  -- the wrap is still a no-op for staleness; the marker must not log.
  OptionsMenu.dramaticShapeFullHook = false

  function OptionsMenu.new(game)
    local rows = {}
    local g = game or live()
    -- Same descriptor list OPTION draws (cart + pipelines + hook), so a
    -- Gen 1-style rebuild after crossing VOXEL FULL sees TILT dropped and
    -- FULL-owned rows gone -- matching Emerald's OptionsMenu.new.
    local reader = g and (g.optionAllDescriptors or g.optionExtraRows)
    if type(reader) == "function" then
      local ok, got = pcall(reader, g)
      if ok and type(got) == "table" then rows = got end
    end
    return setmetatable({ game = g, rows = rows, index = 1, scroll = 0 },
      OptionsMenu)
  end

  -- Ruby drives its own screen via optionMenuSpec; this update exists so the
  -- mod's FULL-crossing wrapper can rebuild `self.rows` from new() without
  -- throwing. Refreshing from optionAllDescriptors keeps the Gen 1 patch
  -- honest even though Ruby's drawn list does not read this module.
  function OptionsMenu:update(_dt)
    local g = self.game or live()
    local reader = g and (g.optionAllDescriptors or g.optionExtraRows)
    if type(reader) ~= "function" then return end
    local ok, got = pcall(reader, g)
    if ok and type(got) == "table" then self.rows = got end
  end
  function OptionsMenu:draw() end

  return setmetatable(OptionsMenu, {
    __index = function(_, key)
      warnOnce("options." .. tostring(key),
        "src.ui.OptionsMenu.%s has no Gen 3 backing: Ruby's OPTION screen is "
        .. "Game3:optionMenuSpec, which rebuilds every frame -- there is no "
        .. "stale row list to patch", tostring(key))
      return nil
    end,
    __newindex = function(t, key, value) rawset(t, key, value) end,
  })
end

-- ------------------------------------------------------------------- coverage
--
-- Read by the mod manager, and by tests. `backed` means a mod gets the real
-- thing; `warned` means it gets something usable that is not shaped the way
-- Gen 1's is; `absent` means nil and a logged reason.
-- A REAL TextBox, not a stub.
--
-- Served as a softStub, `TextBox.new(game, text, onDone)` handed back an
-- object whose every field resolved to a do-nothing function.  A mod pushed
-- it, Ruby drew an empty frame, and A did not dismiss it -- Wilds' FOLLOW
-- entry ends in exactly that call and froze the game on device.
--
-- Ruby has no Gen 1 state stack to run a real TextBox on; its dialogue is the
-- "talk" field.  So the box built here is a CARRIER: it holds the text and
-- the continuation, and Game3ModWorld's stack push hands both to
-- Game3:openModText, which shows them in the cart's own window.
local function buildTextBox()
  local TextBox = {}

  function TextBox.new(game, text, onDone, opts)
    if type(text) ~= "string" then text = tostring(text or "") end
    return {
      gen3ModText = text,
      onDone = onDone,
      opts = opts,
      game = game,
      -- a caller that tests for a drawable state still sees one; the drawing
      -- itself is Ruby's talk window, not this object
      draw = function() end,
      update = function() end,
    }
  end

  -- everything else keeps the soft-stub shape a Gen 1-shaped mod expects
  return setmetatable(TextBox, {
    __index = function(t, key)
      if type(key) == "string" and key:sub(1, 2) == "__" then return nil end
      local fn = function() return nil end
      rawset(t, key, fn)
      return fn
    end,
  })
end

local COVERAGE = {
  ["src.core.Game"] = {
    kind = "facade",
    target = "src/core/Game3.lua (the live instance)",
    backed = "data input options stack writeOptions overworld world renderer",
    warned = "save",
    notes = {
      save = "Game3 has no Gen 1 save struct; this is the shared launcher "
        .. "options table, which is what the manager and the options screen "
        .. "actually read",
      overworld = "built by src/core/Game3ModWorld.lua over the live Game3 "
        .. "rather than aliased: Ruby has no OverworldController, so the "
        .. "shape is constructed while every field in it stays a live read",
      renderer = "thin setWorldOverride / beginFrame / fitScale / uiSize / "
        .. "worldViewSize seam onto Game3.worldOverride + viewW/viewH; "
        .. "Game3:draw presents override behind the battle UI. Not a full "
        .. "two-pass Renderer; worldViewSize feeds free_fly camera:follow",
    },
  },
  -- `new` is WARNED, not backed: it answers the live map view when the def it
  -- is handed matches a real map, and otherwise a stub whose `blocks` are
  -- empty.  Publishing that as backed would tell an author they always get a
  -- real map; publishing it as absent would hide the half that works.
  ["src.world.Map"] = {
    kind = "facade",
    target = "src/core/Game3.lua map-type readers + Game3:modMapView",
    backed = "isOutdoor isOutside defPassable isPassable blockAt tileAt "
      .. "isWalkableCell isWaterCell inBounds",
    warned = "setBlock cellTile new",
    notes = {
      isOutdoor = "the GBA header stores a map type, so this is read rather "
        .. "than inferred from a tileset name the way Gen 1 does it",
      new = "returns Game3:modMapView for the live/active map when bound, "
        .. "else a soft stub with empty blocks so Map.new never throws",
      blockAt = "routes to modMapView:blockAt (metatile id) when live; "
        .. "nil/0 soft default otherwise -- not a Gen 1 block table",
    },
  },
  ["src.render.GBCFX"] = {
    kind = "stub",
    target = "nothing -- Ruby has no Game Boy Colour filter",
    warned = "setLevel cycle applyOptions isSupported active shader "
      .. "levelLabel present",
    notes = {
      setLevel = "accepted and ignored: a mod calls this to CLEAR the "
        .. "filter, and on Ruby it is already clear",
      present = "returns its canvas unchanged; returning nil would blank "
        .. "the screen",
    },
  },
  ["src.ui.OptionsMenu"] = {
    kind = "stub",
    target = "Game3:optionMenuSpec (a different screen entirely)",
    backed = "new update dramaticShapeFullHook",
    warned = "draw",
    notes = {
      new = "answers the same descriptor list OPTION draws (cart + pipelines "
        .. "+ ui.options.rows), so a Gen 1 rebuild after crossing VOXEL FULL "
        .. "sees the surgically shortened list",
      update = "refreshes rows from optionExtraRows: Ruby's drawn screen "
        .. "still rebuilds every frame, but the mod's FULL-crossing wrap "
        .. "needs a real rebuild target",
      dramaticShapeFullHook = "pre-seeded false so the mod's marker read does "
        .. "not warn; the mod stamps true after wrapping",
    },
  },
  ["src.world.PikachuFollower"] = {
    kind = "adapter",
    target = "nothing -- Hoenn has no overworld follower",
    backed = "current at shouldSpawn starterInParty isStarterPikachu "
      .. "isFollowingDisabled update onStep onMapEntered rebase setVisible "
      .. "talk picLift updateHop hopToCounter bumpHappiness modifyHappiness "
      .. "oaksLabMakeWay onFanClubEntered onBillsHouseEnter "
      .. "onBillWalksAroundPlayer onBillEnteredMachine onBillExitedMachine",
    notes = {
      current = "always nil: Ruby has no follower, which is a true answer "
        .. "rather than a missing one",
      isFollowingDisabled = "true, so a caller deciding whether to suppress "
        .. "its own follower handling skips cleanly. A soft stub answering "
        .. "nil here would read as 'following is enabled'",
      update = "a no-op, and writable, so a mod that wraps it to steer the "
        .. "follower installs its wrap and does nothing",
    },
  },
  -- Writable Player adapter with softStub-matching __index: `__*` stamps stay
  -- nil until assigned; other missing keys become cached no-op callables.
  ["src.world.Player"] = {
    kind = "adapter",
    target = "nothing -- Ruby's overworld actor is Game3 field state, not Gen 1 Player",
    backed = "new update draw pose walkPhase facePlayer",
    notes = {
      new = "returns an empty instance table; Gen 3 does not place Gen 1 Player records",
      update = "honest no-op so free_fly (and similar) can wrap without nil guards",
      draw = "honest no-op; free_fly wraps module draw for flat Gen 1 compose",
      pose = "honest no-op; free_fly wraps module pose and reassigns __freeFlyPoseImpl",
      ["__freeFlyMount / __freeFlyMountScale / __freeFlyBird"] =
        "writable stamp fields; __index leaves `__*` as nil (never caches a function)",
    },
  },
  ["src.ui.PartyMenu"] = {
    kind = "adapter",
    target = "Game3:monIconFrame + Game3:drawMonIcon",
    backed = "drawIcon mirrorsIcon frameFor",
    absent = "new",
    notes = {
      drawIcon = "the real thing: Game3 owns both the frame choice (read off "
        .. "the mon's HP, as Gen 1 does) and the atlas blit",
      mirrorsIcon = "false for every species: Gen 3 icons are a plain atlas, "
        .. "so nothing is Gen 1's asymmetric HELIX case",
      new = "Ruby's party screen is a Game3 field state, not a Gen 1 stack "
        .. "state; open it through the game",
    },
  },
  ["src.world.NPC"] = {
    kind = "adapter",
    target = "Game3ModWorld actorView (plain object-event records)",
    backed = "new pose walkPhase update facePlayer resetToSpawn",
    absent = "draw",
    notes = {
      new = "builds the Gen 1 record shape -- cellX/cellY, px/py, facing and "
        .. "Ruby's sprite DEF resolved through data.sprites.byId -- but does "
        .. "NOT place it: Ruby draws the object events its map declares and "
        .. "has no runtime-object store (same gap mod.world:spawnNpc names)",
      walkPhase = "movement.asm's own 16-tick phase window, unchanged",
      draw = "a Gen 1 SpriteRenderer would paint through the wrong pipeline "
        .. "at the wrong scale; read pose() and draw it yourself",
    },
  },
  ["src.ui.OptionRows"] = {
    kind = "adapter",
    target = "src/ui/OptionRows.lua's arithmetic; nothing for the draw",
    backed = "VISIBLE clampScroll",
    warned = "draw",
    notes = {
      clampScroll = "pure list arithmetic, identical in both games",
      draw = "inert: it paints Red's 160x144 four-box viewport through Gen 1's "
        .. "Font and Theme, and Ruby's OPTION screen is a Game3 field state on "
        .. "a 240x160 surface. Present so a mod that wraps it still loads",
    },
  },
  ["src.ui.Screens"] = {
    kind = "adapter",
    target = "Game3:openStartMenu / Game3:openModScreen (field + StateStack)",
    backed = "push register",
    warned = "pop",
    notes = {
      push = "backed names open Ruby field menus; registered / data.screens "
        .. "factories open via Game3:openModScreen (same rails as the mod "
        .. "manager -- letterboxed 160x144). Unknown names still refuse once",
      register = "stores the factory for a later push (qol_toggles "
        .. "QolTogglesMenu); also resolved from game.data.screens",
    },
  },
  ["src.world.Collision"] = {
    kind = "adapter",
    target = "src/world/gen3/Collision.lua",
    backed = "occupied",
    warned = "canMove load blocked",
    notes = {
      occupied = "generation-agnostic: it reads only the entity list handed "
        .. "to it, so the same answer is right on either generation",
      canMove = "Ruby answers passability through the map view "
        .. "(isWalkableCell / isWaterCell / elevationAt), not a block table",
    },
  },
  ["src.world.OverworldController"] = {
    kind = "adapter",
    target = "src/world/gen3/OverworldAPI.lua over Game3:gridHandleInput",
    backed = "handleInput pushBattle",
    notes = {
      handleInput = "Ruby's own pad read, which Game3:fieldHandleInput now "
        .. "routes through this module -- so a mod that replaces the walk by "
        .. "wrapping it is in the engine's path, not beside it. The push "
        .. "verbs (checkEdgeExit and the rest) are called on the STATE, not "
        .. "on this module, and live on the overworld view instead",
      pushBattle = "no-op body: Ruby already owns the fight on Game3.battle. "
        .. "Exists so DRAMATIC_SHAPE can wrap it; Gen3Compat bridges "
        .. "Game3:launchBattleWithEntrance onto this method so begin() runs",
    },
  },
  ["src.battle.BattleState"] = {
    kind = "facade",
    target = "Game3.battle + Game3:drawBattle / finishBattle (thin)",
    backed = "finish draw resolveBattleScale backPlacement frontPlacement "
      .. "picImage uiSize growInScale isWideBattleLayout isOpaque "
      .. "dramaticShapeBattleHook dramaticShapeExitHook "
      .. "showEnemyTrainer showPlayerBack introBalls blankForAskName "
      .. "drawPicsLayer",
    warned = "drawTextArea drawAnimLayer drawZonePass drawHUDs",
    absent = "newWild newTrainer makeBattler resolveTurn enter exit "
      .. "sgbPalettes renderer",
    notes = {
      finish = "routes to Game3:finishBattle; DRAMATIC_SHAPE wraps this for "
        .. "the voxel exit fade",
      draw = "routes to Game3:drawBattle through a battle view; staged "
        .. "3D-BTL sets Game.renderer worldOverride for Game3:draw to blit",
      drawPicsLayer = "draws via Game3:drawBattlePic / battlerTopLeft so "
        .. "DRAMATIC_SHAPE sideTexture can capture billboard canvases; "
        .. "flags default false and mirror introCinemaVisuals when present",
      resolveBattleScale = "Gen 3 defaults (front=1, back=1), pure math",
      showEnemyTrainer = "seeded false; live value from introCinemaVisuals "
        .. "or host.battle when set",
      showPlayerBack = "Gen 1 name for Game3 introCinemaVisuals.showPlayerTrainer",
    },
  },
}

-- ------------------------------------------------------------- src.ui.Screens
--
-- Gen 1's screen stack, which Ruby does not have: its menus are `game.field`
-- states stepped by Game3. A mod reaching for it used to get Gen 1's module
-- and Gen 1's screens (DRAMATIC_SHAPE's START -> Gen 1 StartMenu crash).
--
-- Phase 4: backed field openers stay, AND registered / data.screens factories
-- open through Game3:openModScreen -- the same StateStack + letterbox rails
-- the mod manager already uses. That is enough for qol_toggles'
-- QolTogglesMenu (title + toggle rows over save.options) without cloning
-- Gen 1's full StateStack.

local SCREENS_UNBACKED = {
  HordeExitPrompt = "Ruby has no screen stack to push a mod prompt onto; its "
    .. "menus are Game3 field states",
  HordeGameOver = "Ruby has no screen stack to push a mod prompt onto; its "
    .. "menus are Game3 field states",
}

-- Factories from Screens.register OR resolved from game.data.screens.
local SCREENS_FACTORIES = {}

-- Names that open a real Game3 field / opener. Keep this table narrow: only
-- screens that have a Ruby equivalent. A registered but empty push is worse
-- than a logged refusal, because the mod thinks a prompt is up.
local SCREENS_BACKED = {
  StartMenu = function(g)
    local okI, Input = pcall(require, "src.core.Input")
    if okI and Input and Input.wasPressed and Input:wasPressed("start") then
      return true
    end
    return g:openStartMenu()
  end,
  Option = function(g)
    g.field = { kind = "option", cursor = 0 }
    return true
  end,
  Options = function(g)
    g.field = { kind = "option", cursor = 0 }
    return true
  end,
  OptionsMenu = function(g)
    g.field = { kind = "option", cursor = 0 }
    return true
  end,
  Party = function(g)
    if type(g.openParty) == "function" then return g:openParty() end
  end,
  PartyMenu = function(g)
    if type(g.openParty) == "function" then return g:openParty() end
  end,
  Bag = function(g)
    if type(g.openBag) == "function" then return g:openBag() end
  end,
  BagMenu = function(g)
    if type(g.openBag) == "function" then return g:openBag() end
  end,
}

local function resolveScreenFactory(g, name)
  local hit = SCREENS_FACTORIES[name]
  if hit then return hit end
  -- Live content registry keeps the factory function even if a merge path
  -- ever stripped it from data.screens; qol registers only via content.screens.
  local loader = g and g.mods
  local reg = loader and loader.content and loader.content.screens
  if reg and type(reg.get) == "function" then
    local ok, value = pcall(reg.get, reg, name)
    if ok and value ~= nil then
      local factory = nil
      if type(value) == "function" then
        factory = { new = value }
      elseif type(value) == "table" and type(value.new) == "function" then
        factory = value
      end
      if factory then
        SCREENS_FACTORIES[name] = factory
        return factory
      end
    end
  end
  local screens = g and g.data and g.data.screens
  local record = screens and screens[name]
  if record == nil then return nil end
  local factory = nil
  if type(record) == "function" then
    factory = { new = record }
  elseif type(record) == "table" and type(record.new) == "function" then
    factory = record
  end
  -- Cache so a later Screens.push still works if data.screens is rebuilt,
  -- and so Screens.register / content.screens share one lookup table.
  if factory then SCREENS_FACTORIES[name] = factory end
  return factory
end

-- The facade Screens table, kept so the ENGINE-side ModUI can be routed into
-- it (see armModUiPush).  buildScreens is memoised by the facade's own module
-- table, so this holds the one instance mods are served.
local gen3ScreensFacade = nil

local function buildScreens()
  -- One instance for the whole boot: the sandbox serves it to mods and
  -- armModUiPush routes the engine's ModUI into the same table, so a screen
  -- registered through either path is reachable from both.
  if type(gen3ScreensFacade) == "table" then return gen3ScreensFacade end
  local Logger = require("src.core.Logger")
  local Screens = {}
  local warned = {}
  local function game()
    local g = resolveGame and resolveGame()
    if type(g) == "table" and type(g.openStartMenu) == "function" then
      return g
    end
    return nil
  end
  function Screens.push(gameOrNil, name, ...)
    -- Gen 1 signature is Screens.push(game, id, ...); the first arg may be
    -- the live game or nil when a mod used the bound resolveGame path.
    local g = gameOrNil
    if not (type(g) == "table" and type(g.openStartMenu) == "function") then
      g = game()
    end
    local opener = SCREENS_BACKED[name]
    if opener then
      if not g then return nil end
      return opener(g)
    end
    local factory = resolveScreenFactory(g, name)
    if factory and g and type(g.openModScreen) == "function" then
      -- qol_toggles' factory runs Font.width / card layout at new() time.
      -- openModScreen's ensureManagerFont is TOO LATE -- a FONT3 boot throws
      -- inside factory.new and Screens.push returns nil (QOL row A looks dead).
      if type(g.ensureManagerFont) == "function" then
        pcall(g.ensureManagerFont, g)
      end
      -- Arm Input the way openModScreen does, so factory/update can read it.
      if g.input == nil then
        local okI, Input = pcall(require, "src.core.Input")
        if okI then g.input = Input end
      end
      local ok, inst = pcall(factory.new, g, ...)
      if ok and type(inst) == "table" then
        inst.screenId = inst.screenId or name
        local opened = g:openModScreen(inst)
        if opened then return inst end
        Logger.info("gen3 facade: src.ui.Screens.push(%s) openModScreen failed",
          tostring(name))
        return nil
      end
      if not warned["fail:" .. tostring(name)] then
        warned["fail:" .. tostring(name)] = true
        Logger.info("gen3 facade: src.ui.Screens.push(%s) factory error: %s",
          tostring(name), tostring(inst))
      end
      return nil
    end
    local key = tostring(name)
    if not warned[key] then
      warned[key] = true
      Logger.info("gen3 facade: src.ui.Screens.push(%s) has no Gen 3 screen: %s",
        key, SCREENS_UNBACKED[key]
          or "no factory registered and Ruby has no builtin for this id")
    end
    return nil
  end
  -- popping is Ruby's own menu code's business for field menus; for a mod
  -- screen the instance's exit() pops the StateStack (see openModScreen).
  function Screens.pop()
    local g = game()
    if g and g.stack and type(g.stack.pop) == "function" then
      return g.stack:pop()
    end
    return nil
  end
  -- register: store the factory so a later push can openModScreen it
  -- (qol_toggles registers QolTogglesMenu this way AND via content.screens).
  function Screens.register(name, factory)
    if type(name) ~= "string" then return end
    if SCREENS_BACKED[name] then return end
    if type(factory) == "function" then
      SCREENS_FACTORIES[name] = { new = factory }
    elseif type(factory) == "table" and type(factory.new) == "function" then
      SCREENS_FACTORIES[name] = factory
    else
      return
    end
    -- a registered factory is no longer an unbacked refusal
    SCREENS_UNBACKED[name] = nil
  end
  gen3ScreensFacade = Screens
  return Screens
end

-- ----------------------------------------------------- src.battle.BattleState
--
-- Gen 1's BattleState is engine AND screen on one table. Emerald keeps that
-- shape (src/battle/BattleState.lua + Gen3Battle composition). Ruby folds the
-- fight into Game3 itself -- self.battle is a plain table, drawBattle /
-- finishBattle are methods on the game -- so there is no BattleState module
-- to alias.
--
-- DRAMATIC_SHAPE still requires this name: OverworldBattle.install and
-- BattleExit.install wrap finish / draw / placement / layer methods on the
-- MODULE TABLE, expecting instances to inherit them. Served as a thin
-- facade: pure placement helpers are real, finish/draw trampoline into the
-- captured Game3 methods through a battle VIEW, and the per-layer draws are
-- stubs (Ruby has no separate pics/HUD/anim layers to wrap into). The
-- world-override seam lives on Game.renderer (translate.renderer) so a
-- staged BattleState:draw can composite the arena canvas like Emerald.
--
-- Bridging matters the way OverworldAPI.handleInput does: a wrap on this
-- table has to be what the engine calls, not a copy sitting beside it.

local function buildBattleState()
  local BattleState = {}
  BattleState.__index = BattleState
  BattleState.isOpaque = true
  -- Pre-seeded so DRAMATIC_SHAPE's `if not BattleState.dramaticShape*Hook`
  -- reads do not trip the __index warn before the mod stamps true.
  BattleState.dramaticShapeBattleHook = false
  BattleState.dramaticShapeExitHook = false

  -- Gen 1 BattleState instance fields DRAMATIC_SHAPE reads every frame.
  -- Without these, asBattle.__index fell through to the module metatable and
  -- logged "no Gen 3 backing" spam (and returned nil) for each lookup.
  BattleState.showEnemyTrainer = false
  BattleState.showPlayerBack = false
  BattleState.introBalls = false
  BattleState.blankForAskName = false

  BattleState.BATTLE_SCALE_DEFAULT = { front = 1, back = 2 }
  BattleState.BATTLE_SCALE_GEN3 = { front = 1, back = 1 }

  local function imageBattleScale(scales, path)
    if type(scales) ~= "table" or type(path) ~= "string" then return nil end
    local row = scales[path]
    if type(row) == "number" then return row end
    if type(row) == "table" then
      return row.scale or row[1] or row.front or row.back
    end
    return nil
  end

  function BattleState.imageBattleScale(scales, path)
    return imageBattleScale(scales, path)
  end

  function BattleState.resolveBattleScale(data, side, path, species)
    local img = data and imageBattleScale(data.battle_sprite_scales, path)
    if img then return img end
    local def = species and data and data.pokemon and data.pokemon[species]
    local field = side == "back" and "battleScaleBack" or "battleScaleFront"
    local override = def and def[field]
    if override then return override end
    local defaults = BattleState.BATTLE_SCALE_GEN3
    return defaults[side] or 1
  end

  function BattleState.backPlacement(w, h, pad, padL, scale)
    return 8 - padL * scale, 96 - (h - pad) * scale, scale
  end

  function BattleState.frontPlacement(ex, ey, w, h, scale)
    return ex + w * (1 - scale) / 2, ey + h * (1 - scale), scale
  end

  function BattleState:picImage(img)
    return img
  end

  function BattleState:uiSize()
    return 240, 160
  end

  function BattleState:isWideBattleLayout()
    return false
  end

  function BattleState:growInScale(_battler)
    return nil
  end

  function BattleState:shrinkOutScale(_battler)
    return nil
  end

  -- Layer helpers: Ruby composites most UI inside Game3:drawBattle, but
  -- DRAMATIC_SHAPE 3D-BTL captures mon billboards by calling drawPicsLayer
  -- into an offscreen canvas. That path needs a real draw, not a no-op.
  function BattleState:drawPicsLayer(slide, sx, sy, onlySide, _skipMenuClip)
    local host = self._host or live()
    if not (host and type(host.drawBattlePic) == "function"
            and type(host.battlerTopLeft) == "function") then
      return
    end
    sx, sy = sx or 0, sy or 0
    local function want(side)
      -- onlySide 0 was an old bug; treat it like nil (draw all).
      return not onlySide or onlySide == 0 or onlySide == side
    end
    local function shinyOf(mon)
      if type(host.isShinyMon) == "function" then
        local ok, s = pcall(host.isShinyMon, host, mon)
        return ok and s or false
      end
      return false
    end
    local function imgDims(img)
      local w, h = 64, 64
      if img and img.getDimensions then
        local okD, dw, dh = pcall(img.getDimensions, img)
        if okD and dw and dh and dw > 0 and dh > 0 then w, h = dw, dh end
      end
      return w, h
    end
    local function drawMon(side, which, mon)
      if not (mon and mon.species) then return end
      if mon.invuln then return end
      if type(mon.hp) == "number" and mon.hp <= 0 then return end
      local shiny = shinyOf(mon)
      -- Publish .sprite before draw so BattleArt / foot-pad / visibility
      -- see the same image the layer is about to blit.
      local img
      if type(host.battlePic) == "function" then
        local okI, got = pcall(host.battlePic, host, mon.species, which, shiny)
        if okI then img = got end
      end
      if img then mon.sprite = img end
      local w, h = imgDims(img)
      local scale, px, py = 1, 0, 0
      -- Go through BattleState.frontPlacement / backPlacement so DRAMATIC_SHAPE
      -- OverworldBattle can pin the pic to TEX_AX/TEX_AY while capturing a
      -- billboard. Drawing at battlerTopLeft (enemy x=144 on a 160-wide GB
      -- canvas) left Wurmple off the card: player at x=40 stayed visible.
      --
      -- The stock back helper is one GB feet-slot for the whole side. In a
      -- double that paints both player backs on the same pixels (the partner
      -- sitting inside the lead's missing-pic square). A capture pin moves
      -- that x off the stock slot; keep the pin. Otherwise each back uses
      -- its own battler mark.
      local ok, tx, ty = pcall(host.battlerTopLeft, host, side, mon.species, which)
      local slotX = (ok and tx) or 0
      local slotY = (ok and ty) or 0
      local doubles = host.battle and host.battle.doubles
      if which == "back" then
        local bx, by, bs = BattleState.backPlacement(w, h, 0, 0, scale)
        local pinned = bx and math.abs(bx - 8) > 2
        -- Singles keeps the GB feet-slot. Doubles uses each battler's own
        -- mark unless a billboard capture has pinned this draw.
        if pinned or not doubles then
          px, py, scale = (bx or 0) + sx, (by or 0) + sy, bs or scale
        else
          px, py = slotX + sx, slotY + sy
        end
      else
        local fx, fy, fs = BattleState.frontPlacement(slotX, slotY, w, h, scale)
        px, py, scale = (fx or slotX) + sx, (fy or slotY) + sy, fs or scale
      end
      pcall(host.drawBattlePic, host, mon.species, which, px, py, scale, 0, false,
            shiny)
    end

    local okG, G3 = pcall(require, "src.core.Game3")
    local cxT = (okG and G3 and G3.BATTLER_CX) or {}
    local cyT = (okG and G3 and G3.BATTLER_CY) or {}

    if want("enemy") and self.showEnemyTrainer and self.trainerPic then
      local img = self.trainerPic
      if type(img) == "userdata" then
        local cx = cxT.enemy or 176
        local cy = cyT.enemy or 40
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, cx - 32 + sx, cy - 32 + sy)
      end
    elseif want("enemy") then
      drawMon("enemy", "front", self.enemy)
      if self.enemy2 then drawMon("enemy2", "front", self.enemy2) end
    end

    if want("player") and self.showPlayerBack and self.playerBackPic then
      local img = self.playerBackPic
      if type(img) == "userdata" then
        local cx = cxT.player or 72
        local cy = cyT.player or 80
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, cx - 32 + sx, cy - 40 + sy)
      end
    elseif want("player") then
      drawMon("player", "back", self.player)
      if self.player2 then drawMon("player2", "back", self.player2) end
    end
  end
  function BattleState:drawTextArea() end
  function BattleState:drawAnimLayer() end
  function BattleState:drawZonePass() end
  function BattleState:drawHUDs() end

  -- Captured Game3 methods, filled by bridgeEngine below. Defaults call
  -- through the host game so a wrap that chains to inner still reaches Ruby.
  local origDraw, origFinish

  function BattleState:draw()
    local host = self._host or live()
    if host and origDraw then return origDraw(host) end
  end

  function BattleState:finish()
    local host = self._host or live()
    if host and origFinish then return origFinish(host) end
  end

  -- A battle VIEW: reads Game3.battle fields, writes go back onto that table,
  -- methods resolve on this facade. `game` is the live Game3 (which publishes
  -- stack / overworld via publishModWorld).
  local function cinemaFlags(host)
    if not (host and type(host.introCinemaVisuals) == "function") then
      return nil
    end
    local ok, vis = pcall(host.introCinemaVisuals, host)
    if not (ok and type(vis) == "table") then return nil end
    return vis
  end

  -- DRAMATIC_SHAPE sideVisible used to require battler.sprite, which Gen 1
  -- stamps and Ruby never does. Look the pic up once so billboard capture
  -- and foot-pad measurement see the same image drawPicsLayer blits.
  local function stampBattleSprites(host)
    local b = host and host.battle
    if type(b) ~= "table" or type(host.battlePic) ~= "function" then return end
    local function stamp(mon, which)
      if type(mon) ~= "table" or mon.species == nil then return end
      local shiny = false
      if type(host.isShinyMon) == "function" then
        local okS, s = pcall(host.isShinyMon, host, mon)
        shiny = okS and s or false
      end
      local okI, img = pcall(host.battlePic, host, mon.species, which, shiny)
      if okI and img then mon.sprite = img end
    end
    stamp(b.player, "back")
    stamp(b.player2, "back")
    stamp(b.enemy, "front")
    stamp(b.enemy2, "front")
  end

  local function asBattle(host)
    stampBattleSprites(host)
    local bag = (host and host.battle) or {}
    local view = { _host = host, game = host }
    return setmetatable(view, {
      __index = function(_, key)
        if key == "game" then return host end
        if key == "_host" then return host end
        local v = bag[key]
        if v ~= nil then return v end
        -- Map Gen 1 billboard flags onto Game3 intro cinema visuals so
        -- BattleVisibility / BattleArt see the same truth drawBattle uses.
        if key == "showEnemyTrainer" or key == "showPlayerBack"
            or key == "introBalls" or key == "blankForAskName"
            or key == "enemyHidden" or key == "sendingOut" then
          local vis = cinemaFlags(host)
          if vis then
            if key == "showEnemyTrainer" then return vis.showEnemyTrainer and true or false end
            if key == "showPlayerBack" then return vis.showPlayerTrainer and true or false end
            if key == "introBalls" then return (vis.balls or vis.ball) and true or false end
            if key == "blankForAskName" then return false end
            -- Game3 uses introCinemaVisuals.*Hide, not Gen 1 enemyHidden.
            if key == "enemyHidden" then return vis.enemyHide and true or false end
            if key == "sendingOut" then return vis.playerHide and true or false end
          end
        end
        -- rawget: avoid the module __index warn spam for ordinary data misses
        local m = rawget(BattleState, key)
        if m ~= nil then return m end
        return nil
      end,
      __newindex = function(_, key, value)
        if key == "game" or key == "_host" then
          rawset(view, key, value)
          return
        end
        if host and host.battle then
          host.battle[key] = value
        else
          rawset(view, key, value)
        end
      end,
    })
  end

  local bridged = false
  local function bridgeEngine()
    if bridged then return end
    bridged = true
    local ok, Game3 = pcall(require, "src.core.Game3")
    if not ok or type(Game3) ~= "table" then return end
    pcall(require, "src.core.Game3BattleTransition")

    origDraw = Game3.drawBattle
    origFinish = Game3.finishBattle
    local origLaunch = Game3.launchBattleWithEntrance

    if type(origDraw) == "function" then
      function Game3:drawBattle()
        local draw = BattleState.draw
        if type(draw) == "function" then
          return draw(asBattle(self))
        end
        return origDraw(self)
      end
    end

    if type(origFinish) == "function" then
      function Game3:finishBattle()
        local finish = BattleState.finish
        if type(finish) == "function" then
          return finish(asBattle(self))
        end
        return origFinish(self)
      end
    end

    -- Gen 1 emits battle.ended after the pop; Ruby's endBattle never did, so
    -- DRAMATIC_SHAPE's handler (OverworldBattle.finish) never ran on a
    -- hard-cut exit. Mirror the event and clear the worldOverride seam here.
    local origEnd = Game3.endBattle
    if type(origEnd) == "function" and not Game3.dramaticShapeEndBattleHook then
      function Game3:endBattle(...)
        local result = origEnd(self, ...)
        pcall(function()
          self.worldOverride = nil
          local r = rawget(self, "_modRenderer") or self.renderer
          if r and r.setWorldOverride then r:setWorldOverride(nil) end
          if type(self.syncWorldView) == "function" then self:syncWorldView() end
          if type(self.clampCamera) == "function" then self:clampCamera() end
        end)
        pcall(function()
          require("src.mods.Runtime").emit("battle.ended", {
            game = self, result = self.battleOutcome,
          })
        end)
        return result
      end
      Game3.dramaticShapeEndBattleHook = true
    end

    if type(origLaunch) == "function" then
      function Game3:launchBattleWithEntrance(opts)
        local ow = rawget(self, "overworld")
        if type(ow) ~= "table" and type(self.modOverworld) == "function" then
          local okOw, view = pcall(self.modOverworld, self)
          if okOw then ow = view end
        end
        local okApi, OverworldAPI = pcall(require, "src.world.gen3.OverworldAPI")
        if okApi and ow and type(OverworldAPI.pushBattle) == "function" then
          pcall(OverworldAPI.pushBattle, ow, asBattle(self))
        end
        return origLaunch(self, opts)
      end
    end
  end

  bridgeEngine()

  return setmetatable(BattleState, {
    __index = function(_, key)
      -- Data-flag lookups are answered above via rawget defaults; only warn
      -- when something probes an unknown API name on the module itself.
      warnOnce("battle." .. tostring(key),
        "src.battle.BattleState.%s has no Gen 3 backing: Ruby's fight lives "
        .. "on Game3 (self.battle / drawBattle / finishBattle), not a "
        .. "separate BattleState class", tostring(key))
      return nil
    end,
    -- wraps must land on THIS table (Game3 bridges read BattleState.draw etc.)
    __newindex = function(t, key, value) rawset(t, key, value) end,
  })
end



-- --------------------------------------------------------------- src.world.NPC
--
-- Soft stub only. Ruby NPCs are plain object-event records on the map, drawn
-- through Game3ModWorld actor views -- there is no Gen 1 NPC class to alias.
-- weather_fx / overworld_wild_spawns that `require("src.world.NPC")` must not
-- hard-fail; constructing via NPC.new returns a plain table the mod can stash.

-- TRANSLATING RED'S SPRITE DIALECT, at module scope because two callers need
-- it: the NPC facade reads through it, and the loader now COERCES through it.
--
-- A Gen 1-shaped mod says { image, frames, walker }; Ruby says
-- { path, frameCount, width, height }.  The mapping is total -- every Red key
-- has a Ruby name and the two sizes default to one metatile -- which is what
-- makes translating safe where guessing would not be.  Both spellings are kept
-- on the way out so a consumer of either vocabulary reads the same record.
local function normalizeModSprite(def, id)
  if type(def) ~= "table" then return nil end
  local image = def.image or def.path
  if type(image) ~= "string" or image == "" then return def end
  local frames = tonumber(def.frames) or tonumber(def.frameCount) or 1
  local width = tonumber(def.width) or tonumber(def.frameWidth) or 16
  local height = tonumber(def.height) or tonumber(def.frameHeight) or 16
  local need = def.path ~= image
    or def.image ~= image
    or def.frames ~= frames
    or def.frameCount ~= frames
    or def.width ~= width
    or def.height ~= height
    or (id ~= nil and def.id == nil)
  if not need then return def end
  local out = {}
  for k, v in pairs(def) do out[k] = v end
  out.id = out.id or id
  out.image = image
  out.path = image
  out.frames = frames
  out.frameCount = frames
  out.width = width
  out.height = height
  return out
end

-- The one entry point the loader calls: given a registry name and a record a
-- mod registered, return a version this generation can store, or nil when
-- there is no honest translation.  Only sprites have one today; a registry
-- absent from here keeps the strict answer, which is the safe default.
-- `id` is the REGISTRY KEY, not value.id: a mod usually registers
-- { image = ..., frames = 1 } with no id inside the record at all, and the
-- name it registered under is the only id there is.  Passing value.id left
-- that field empty and the translated record still failed validation on it.
-- The 32px directional art the Wilds mod shows in its own preview menu.
--
-- The mod ships its overworld art twice.  Registration picks
-- assets/generated/followsprites_runtime -- a 16x96 six-frame downscale, in
-- which a Hoenn species is a coloured smudge rather than a recognisable
-- Pokemon, which is the complaint.  The art its preview browser lists sits
-- beside it in assets/enhanced_overworld/followsprites at 32px (64px for a
-- dozen large species) and covers all 135 Hoenn species; the mod reports it
-- READY with 649 mapped species on Ruby, and simply never registers it,
-- because its own animated path needs a companion pack that only reaches
-- dex 251 and so cannot serve Hoenn at all.
--
-- Layout, from the mod's followsprites_mapping.json:
--   4 columns x 4 rows; ROWS ARE DIRECTIONS (down/left/right/up), COLUMNS
--   ARE WALK FRAMES, and the tile is imageWidth / 4.
-- Read off the image, not the mapping: the mapping is 550KB of JSON and the
-- only two facts it carries that the image does not are the form letter,
-- which is one getInfo to probe, and a tile size that is always width/4 in
-- every one of its 649 entries.
--
-- Derived from the record's OWN path rather than a literal "mods/..." root,
-- so an install under the save directory resolves exactly as the record did.
--
-- CONTRACT: returns (desc, image) only when the image is already loaded, and
-- nil otherwise.  A caller can therefore swap unconditionally on a non-nil
-- return without any chance of claiming the draw slot and painting nothing --
-- the failure that the 2026-09-25 enhanced-art attempt shipped.
local WILDS_HI_ROW = { down = 0, left = 1, right = 2, up = 3,
  south = 0, west = 1, east = 2, north = 3 }
local WILDS_HI_FORMS = { "b", "m", "f" }
local wildsHiCache = {}

function Gen3Compat.wildsEnhancedSheet(game, entity, currentPath)
  if type(currentPath) ~= "string" then return nil end
  local head, tail = currentPath:match("^(.*)assets/generated/followsprites_runtime/(.+)$")
  -- TWO WAYS IN, BECAUSE THE TWO GUEST KINDS ARRIVE DIFFERENTLY.
  --
  -- A wild spawn still carries its registered runtime-sheet path, so the
  -- enhanced file has to be found for it.  A follower is repointed at the
  -- enhanced file earlier, by refreshGuestSprite -- but with no grid
  -- metadata, so the blit read it as a 16px strip and cropped the top-left
  -- corner of a 4x4 grid: one facing, whichever way the guest was walking.
  -- Recognising the enhanced path as well lets both kinds share one
  -- descriptor, and keeps the draw a single code path.
  local given = nil
  if not head then
    local h2, file = currentPath:match(
      "^(.*)assets/enhanced_overworld/followsprites/([^/]+%.png)$")
    if not h2 then return nil end
    -- the grayscale companions are a different asset; leave them alone
    if file:find("grayscale", 1, true) then return nil end
    head, given, tail = h2, file, file
  end
  local dex = tonumber(tail:match("^(%d+)%-"))
  if not dex then return nil end
  local shiny = false
  if type(entity) == "table" then
    shiny = entity.shiny == true or entity.isShiny == true
  end
  -- KEYED BY ROOT AS WELL AS SPECIES.  The root comes from the record, and a
  -- mod installed under the save directory has a different one, so a key of
  -- species alone would hand the second install the first one's paths.
  local key = head .. (given or tostring(dex)) .. (shiny and ":s" or ":n")
  local hit = wildsHiCache[key]
  if hit ~= nil then
    if hit == false then return nil end
    return hit, hit.imageObj
  end
  if not (love and love.filesystem and love.filesystem.getInfo
      and love.graphics and love.graphics.newImage) then
    return nil
  end
  local suffix = shiny and "s" or "n"
  local dir = head .. "assets/enhanced_overworld/followsprites/"
  -- An already-enhanced path is taken exactly as given: it is the file the
  -- mod picked, and re-deriving it from the dex would second-guess that.
  local candidates = {}
  if given then
    candidates[1] = dir .. given
  else
    for i = 1, #WILDS_HI_FORMS do
      candidates[i] = ("%s%03d-%s-%s.png"):format(dir, dex, WILDS_HI_FORMS[i], suffix)
    end
  end
  for i = 1, #candidates do
    local rel = candidates[i]
    if love.filesystem.getInfo(rel) then
      -- NEAREST, ALWAYS.
      --
      -- LOVE's default filter is LINEAR, and Game3:grabImage -- which every
      -- other sheet in the world pass goes through -- sets nearest on the way
      -- in.  Loading this one with newImage alone left it linear, so the
      -- hard alpha edge blended with the fully transparent surround and the
      -- guest came out looking semi-transparent on device.  The art itself is
      -- strictly binary alpha: 0 or 255, no partial pixels anywhere.
      local img
      if type(game) == "table" and type(game.grabImage) == "function" then
        local okG, g = pcall(game.grabImage, game, rel)
        if okG then img = g end
      end
      if not img then
        local okI, i2 = pcall(love.graphics.newImage, rel)
        if okI then img = i2 end
      end
      if img and img.setFilter then pcall(img.setFilter, img, "nearest", "nearest") end
      if img and img.getDimensions then
        local okD, iw, ih = pcall(img.getDimensions, img)
        local cell = okD and math.floor((iw or 0) / 4) or 0
        -- A sheet that is not a 4-wide grid of square tiles is not this
        -- layout; leave the guest on its registered art rather than guess.
        if cell >= 16 and ih and math.floor(ih / cell) >= 4 then
          local desc = {
            path = rel,
            image = rel,
            imageObj = img,
            width = cell,
            height = cell,
            cols = 4,
            rows = math.floor(ih / cell),
            dirRows = WILDS_HI_ROW,
            frameCount = 4,
            trueColor = true,
            wildsEnhanced = true,
          }
          wildsHiCache[key] = desc
          return desc, img
        end
      end
    end
  end
  wildsHiCache[key] = false
  return nil
end

function Gen3Compat.coerceRecord(registryName, value, id)
  if registryName ~= "sprites" then return nil end
  if type(value) ~= "table" then return nil end
  local out = normalizeModSprite(value, value.id or id)
  if out == value then return nil end
  return out
end

local function buildNpc()
  local NPC = {}
  NPC.__index = NPC
  local FACING_FROM_RANGE = { DOWN = "down", UP = "up",
                              LEFT = "left", RIGHT = "right" }

  -- Ruby keys its overworld strips by the cart's graphics id under
  -- data.sprites.byId; Gen 1's table is name-keyed.  Resolving the DEF rather
  -- than passing the raw id through is what lets a caller read width/height/
  -- frameCount off the record the way Gen 1's SpriteRenderer let it.
  --
  -- Name-keyed mod registrations (SPRITE_OW_WILD_*) coexist with byId. When
  -- byId exists we still fall through to sprites[id], and Gen1 {image,frames}
  -- records get path/frameCount/width/height aliases so Gen3 pose/draw paths
  -- that read Ruby field names do not see "missing fields".

  local function spriteDefFor(data, id)
    local sprites = data and data.sprites
    if type(sprites) ~= "table" then return nil end
    local byId = sprites.byId
    if type(byId) == "table" then
      local hit = byId[tonumber(id)] or byId[id]
      if hit then return normalizeModSprite(hit, id) end
    end
    local hit = sprites[id]
    if hit then return normalizeModSprite(hit, id) end
    -- Name-keyed Wilds / follower fallbacks (SPRITE_OW_WILD_*) live beside
    -- byId. Also accept a table already carrying image/path (Entity.sprite).
    if type(id) == "table" then
      return normalizeModSprite(id, id.id)
    end
    return nil
  end

  function NPC.new(data, mapId, objDef)
    if type(objDef) ~= "table" then return nil, "objDef must be a table" end
    local def = objDef
    local cellX = tonumber(def.x or def.cellX) or 0
    local cellY = tonumber(def.y or def.cellY) or 0
    local self = setmetatable({
      data = data,
      mapId = mapId,
      def = def,
      id = string.format("%s_obj_%s", tostring(mapId),
                         tostring(def.index or def.localId or "?")),
      x = cellX, y = cellY,
      cellX = cellX, cellY = cellY,
      -- world pixels, so a caller can place the record without knowing the
      -- cell size; Gen 1's NPC carries the same pair
      px = cellX * 16, py = cellY * 16,
      facing = def.facing or FACING_FROM_RANGE[def.range] or "down",
      -- Keep raw sprite name when Wilds passes SPRITE_OW_WILD_* so name-keyed
      -- mod defs still resolve (sprites stay ungated in Schemas.GEN3).
      spriteId = (type(def.sprite) == "string" and def.sprite)
        or (type(def.graphicsId) == "string" and def.graphicsId)
        or nil,
      -- the sprite DEF, not the raw id: Ruby draws these its own way, so a
      -- Gen 1 SpriteRenderer would paint through the wrong pipeline
      sprite = spriteDefFor(data, def.sprite or def.graphicsId),
      moving = false, progress = 0, animClock = 0, stepFlip = false,
      frozen = false,
      -- Side-channel guest only: park on game._modOwGuests. Do NOT inject into
      -- ow.entities/npcs (that path + trackInserts/CAST_KEYS poisoned voxel).
      placed = true,
      _modOwGuest = true,
    }, NPC)
    local game = resolveGame and resolveGame() or nil
    if game then
      Gen3Compat.parkModOwGuest(game, self)
    end
    return self
  end

  -- movement.asm's own phase window, unchanged: a walking NPC shows its step
  -- frame for the middle half of each 16-tick cycle
  function NPC:walkPhase()
    if not self.moving then return 0 end
    local p = (self.animClock or 0) % 16
    return (p >= 4 and p < 12) and 1 or 0
  end

  -- Gen 1's seven values in Gen 1's order, so a caller that draws a pose
  -- itself needs no new branch
  function NPC:pose()
    local flip = self.stepFlip
    if self.moving then
      flip = math.floor((self.animClock or 0) / 16) % 2 == 1
    end
    return self.sprite, self.px, self.py, self.facing,
           self:walkPhase(), flip, false
  end

  function NPC:update(dt)
    if self.frozen or not self.moving then return end
    self.animClock = (self.animClock or 0) + (tonumber(dt) or 0) * 60
  end

  function NPC:facePlayer(px, py)
    local dx = (tonumber(px) or 0) - (self.cellX or 0)
    local dy = (tonumber(py) or 0) - (self.cellY or 0)
    if math.abs(dx) > math.abs(dy) then
      self.facing = dx > 0 and "right" or "left"
    else
      self.facing = dy > 0 and "down" or "up"
    end
    return self.facing
  end

  function NPC:resetToSpawn()
    local d = self.def or {}
    self.cellX = tonumber(d.x or d.cellX) or 0
    self.cellY = tonumber(d.y or d.cellY) or 0
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving, self.progress, self.animClock = false, 0, 0
  end

  -- Flat-path draw for mod guests. Game3:drawActors already translates by
  -- -cam, so callers pass 0,0 (or we ignore cam). Prefer SpriteRenderer when
  -- present; otherwise blit via love.graphics from def.image/path.
  function NPC:draw(camX, camY)
    camX = tonumber(camX) or 0
    camY = tonumber(camY) or 0
    local sprite = self.sprite
    if type(sprite) == "table" and type(sprite.draw) == "function" then
      pcall(sprite.draw, sprite, self.px or 0, self.py or 0, camX, camY,
        self.facing or "down", self:walkPhase(), self.stepFlip)
      return
    end
    local def = sprite
    if type(def) ~= "table" then
      -- Resolve name-keyed SPRITE_OW_WILD_* / fallback if NPC.sprite was nil
      -- at construction (Registered sprites: 0 then later runtime bind).
      def = spriteDefFor(self.data, self.spriteId or (self.def and (self.def.sprite or self.def.graphicsId)))
      if def then self.sprite = def end
    end
    if type(def) ~= "table" then return end
    local path = def.path or def.image
    if type(path) ~= "string" or path == "" then return end
    local G = love and love.graphics
    if not (G and G.draw) then return end
    local img = nil
    if type(def.imageObj) == "userdata" then
      img = def.imageObj
    elseif love and love.graphics and love.graphics.newImage then
      local ok, got = pcall(love.graphics.newImage, path)
      if ok then img = got; def.imageObj = got end
    end
    if not img then return end
    local px = (self.px or 0) - camX
    local py = (self.py or 0) - camY
    G.setColor(1, 1, 1, 1)
    G.draw(img, px, py)
  end
  return setmetatable(NPC, {
    __index = function(_, key)
      warnOnce("npc." .. tostring(key),
        "src.world.NPC.%s has no Gen 3 backing: Ruby NPCs are map object "
        .. "records + Game3ModWorld actor views, not a Gen 1 NPC class",
        tostring(key))
      return nil
    end,
  })
end


-- ------------------------------------------------------- src.ui.OptionRows
--
-- Gen 1's OptionRows draws the OPTIONS list (four 20x4 boxes). Ruby's OPTION
-- screen is Game3 field state and never loads this module, but qol_toggles
-- still requires it on the Gen1 branch to wrap OptionRows.draw for tickers.
-- Serve a tiny stub so the entry chunk does not die on require; Ruby never
-- draws through it (QolTogglesMenu uses its own card grid).

local function buildOptionRows()
  local OptionRows = { VISIBLE = 4 }
  function OptionRows.clampScroll(index, scroll, total, bottomRow)
    index = tonumber(index) or 1
    scroll = tonumber(scroll) or 0
    total = tonumber(total) or 0
    if bottomRow and index >= bottomRow then
      return math.max(0, total - OptionRows.VISIBLE)
    elseif index <= scroll then
      return math.max(0, index - 1)
    elseif index > scroll + OptionRows.VISIBLE then
      return index - OptionRows.VISIBLE
    end
    return scroll
  end
  function OptionRows.draw() end
  return OptionRows
end


-- Soft stubs for Gen 1 modules qol_toggles (and similar) require at entry.
-- Ruby never calls through these; they exist so a missing Gen 1 source file
-- cannot abort the mod's entry chunk after ui.options.rows is already
-- wrapped (which left the QOL menu working while encounter.roll /
-- movement.speed never registered).
-- ------------------------------------------------- src.world.PikachuFollower
--
-- RUBY HAS NO FOLLOWER AT ALL, and that is the whole adapter.  Yellow's
-- Pikachu walks behind the player; Hoenn has nobody, so every question this
-- module answers has a true Gen 3 answer and it is "there isn't one".
--
-- Why answer at all rather than leave it absent: the mods that reach for this
-- do not want a follower, they want to know whether one is in the way.
-- free_fly WRAPS `update` so it can keep the follower off the ground while the
-- player is in the air, and stamps its own fields on the module table to do
-- it; a nil module makes that wrap a crash at load, while a real table whose
-- update does nothing makes it a no-op -- which is exactly right on a game
-- with no follower.  So the table is writable and its verbs are honest zeroes.
--
-- NOT a softStub: a stub answers nil for everything, and
-- `isFollowingDisabled` answering nil reads as "following is ENABLED", which
-- is the opposite of Ruby's truth.
local function buildPikachuFollower()
  local PikachuFollower = {}

  function PikachuFollower.current() return nil end
  function PikachuFollower.at() return nil end
  function PikachuFollower.shouldSpawn() return false end
  function PikachuFollower.starterInParty() return false end
  function PikachuFollower.isStarterPikachu() return false end
  -- DISABLED rather than merely absent: a caller asking this is deciding
  -- whether to suppress its own handling, and "yes, disabled" makes it skip.
  function PikachuFollower.isFollowingDisabled() return true end

  for _, name in ipairs({ "update", "onStep", "onMapEntered", "rebase",
                          "setVisible", "talk", "picLift", "updateHop",
                          "hopToCounter", "bumpHappiness", "modifyHappiness",
                          "oaksLabMakeWay", "onFanClubEntered",
                          "onBillsHouseEnter", "onBillWalksAroundPlayer",
                          "onBillEnteredMachine", "onBillExitedMachine" }) do
    PikachuFollower[name] = function() return nil end
  end

  return PikachuFollower
end

-- --------------------------------------------------------------- src.world.Player
--
-- free_fly (and similar Gen1-shaped flight mods) stamp writable fields on the
-- Player MODULE table:
--   __freeFlyMount, __freeFlyMountScale, __freeFlyBird
-- and wrap pose / draw once via __freeFlyWrapped.
--
-- Writable adapter (not a softStub factory). Named wrap targets are real
-- functions on the table. A softStub-matching __index keeps accidental
-- `Player.something()` from crashing, while keys starting with `__` stay
-- plain nil until the mod stamps them (so `__freeFlyMountScale` is never a
-- cached function that poisons `math.max`).
local function buildPlayer()
  local Player = {}

  function Player.new()
    return {}
  end

  function Player.update() end
  function Player.draw() end
  -- Return a harmless Gen-1-shaped pose tuple so a wrap that calls origPose
  -- before lift is armed does not arithmetic on nil.
  function Player.pose()
    return nil, 0, 0, "down", 0, false
  end
  function Player.walkPhase()
    return 0
  end
  function Player.facePlayer() end

  return setmetatable(Player, {
    __index = function(t, key)
      -- Match softStub rules: never cache no-ops on mod-stamped `__*` data.
      if type(key) == "string" and string.sub(key, 1, 2) == "__" then
        return nil
      end
      local f = function() return nil end
      rawset(t, key, f)
      return f
    end,
  })
end

-- ----------------------------------------------------------- src.ui.PartyMenu
--
-- Only the icon helpers carry over, and they are the ones the mods ask for.
--
-- `drawIcon` is real: Game3 owns both halves of the Gen 1 call -- which frame
-- a mon is on (read off its HP, as Gen 1 does) and blitting it -- so this
-- routes to Game3:monIconFrame + Game3:drawMonIcon rather than reimplementing
-- either.  A softStub would answer nil and draw nothing at all.
--
-- The MENU is absent: `new` builds a Gen 1 stack state, and Ruby's party
-- screen is a Game3 field state with its own input and layout.  The table
-- stays writable because qol_toggles stamps its own fields onto it.
local function buildPartyMenu()
  local Logger = require("src.core.Logger")
  local PartyMenu = {}
  local warned = {}
  local function warnOnce(member, why)
    if warned[member] then return end
    warned[member] = true
    Logger.info("gen3 facade: src.ui.PartyMenu.%s has no Gen 3 backing: %s",
      member, why)
  end

  -- Signature kept from Gen 1 so a caller needs no branch.
  function PartyMenu.drawIcon(game, mon, x, y, selected, counter, forceAlt)
    if type(game) ~= "table" or type(mon) ~= "table" then return false end
    if type(game.drawMonIcon) ~= "function" then return false end
    local frame = 0
    if type(game.monIconFrame) == "function" then
      local ok, value = pcall(game.monIconFrame, game, mon)
      if ok then frame = value or 0 end
    end
    local ok, drew = pcall(game.drawMonIcon, game, mon.species, x, y, frame)
    return ok and drew or false
  end

  -- Gen 3 icons are a plain atlas: no mirrored left half, so nothing is Gen
  -- 1's asymmetric HELIX case and every species draws whole.
  function PartyMenu.mirrorsIcon() return false end

  function PartyMenu.frameFor(_, alt)
    return alt and 1 or 0
  end

  function PartyMenu.new()
    warnOnce("new", "Ruby's party screen is a Game3 field state, not a Gen 1 "
      .. "stack state; open it through the game rather than constructing one")
    return nil
  end

  return PartyMenu
end

-- ------------------------------------------------------------ src.render.Font
--
-- A SOFT STUB IS WRONG FOR A MEASURING FUNCTION.  A stub makes every member
-- exist and answer nil, and a caller written as
--
--     if Font and Font.width then local w = Font.width(text) ... w - 128 ...
--
-- passes its own guard and then does arithmetic on nil.  qol_toggles does
-- exactly that on every map.entered, twice, and crashed the listener.  An
-- ABSENT Font would have been safer than a stubbed one; a measuring Font is
-- safer still, and Ruby can measure -- Game3.textWidth against the live
-- width table is what its own drawText uses to fit a string.
-- Prefer the REAL src/render/Font.lua (draw/drawBox/load). Loading via
-- love.filesystem.load bypasses the facade require shim -- a plain
-- require("src.render.Font") would recurse into this builder and leave
-- qol_toggles painting a blank white 160x144 (width-only stub, no glyphs).
local function loadDiskFont()
  local rel = "src/render/Font.lua"
  if love and love.filesystem and type(love.filesystem.load) == "function" then
    local chunk = love.filesystem.load(rel)
    if type(chunk) == "function" then
      local ok, mod = pcall(chunk)
      if ok and type(mod) == "table" and type(mod.draw) == "function" then
        return mod
      end
    end
  end
  -- Host/test path: read the file next to the package root when present.
  local try = { rel, "./" .. rel }
  for _, p in ipairs(try) do
    local fh = io.open(p, "rb")
    if fh then
      local src = fh:read("*a")
      fh:close()
      if type(src) == "string" and #src > 0 then
        local loader = loadstring or load
        local chunk = loader(src, "@" .. p)
        if type(chunk) == "function" then
          local ok, mod = pcall(chunk)
          if ok and type(mod) == "table" and type(mod.draw) == "function" then
            return mod
          end
        end
      end
    end
  end
  return nil
end

local function armPlainPixelFont(Font)
  -- Ruby's Red font.png in AppData is a ~600B stub: Font.encode warns
  -- "no glyph" for every ASCII letter and menus paint blank white.
  -- Own Plain Pixel and replace draw/encode/width/drawBox on THIS module.
  local ttf
  local function ensureTtf()
    if ttf then return ttf end
    if not (love and love.graphics and love.graphics.newFont) then return nil end
    for _, file in ipairs({
      "assets/fonts/plainpixel/PlainPixel-Regular.ttf",
      "assets/fonts/PlainPixel-Regular.ttf",
    }) do
      -- SIZE 8 IS WHY MOD MENUS WERE UNREADABLE.
      --
      -- The Gen 1 mod UI lays text out for Plain Pixel at its standard size
      -- (src.render.Font.PLAINPIXEL_SIZE = 15).  Built at 8 the glyph
      -- advances come out around 3px -- Font.width("WILDS") answered 15 for
      -- five characters -- so every label drew on top of itself.  It was
      -- never the filter: this font has always been nearest-filtered.
      local size = 15
      do
        local okF, F = pcall(require, "src.render.Font")
        if okF and type(F) == "table" and tonumber(F.PLAINPIXEL_SIZE) then
          size = tonumber(F.PLAINPIXEL_SIZE)
        end
      end
      local ok, obj = pcall(love.graphics.newFont, file, size, "mono", 1)
      if not ok then ok, obj = pcall(love.graphics.newFont, file, size, "normal") end
      if not ok then ok, obj = pcall(love.graphics.newFont, file, size) end
      if ok and obj then
        if obj.setFilter then pcall(obj.setFilter, obj, "nearest", "nearest") end
        ttf = obj
        return ttf
      end
    end
    local ok, obj = pcall(love.graphics.newFont, 8)
    if ok then ttf = obj end
    return ttf
  end

  function Font.width(text)
    text = tostring(text or "")
    local f = ensureTtf()
    if f and f.getWidth then return f:getWidth(text) end
    return #text * 8
  end

  function Font.encode(_text)
    -- Silent: never emit "font: no glyph" on Ruby.
    return {}
  end

  function Font.draw(text, x, y)
    text = tostring(text or "")
    local G = love.graphics
    if not G then return 0 end
    local prev = G.getFont and G.getFont() or nil
    local f = ensureTtf()
    if f then G.setFont(f) end
    local cr, cg, cb, ca = 1, 1, 1, 1
    if G.getColor then cr, cg, cb, ca = G.getColor() end
    -- Tile glyphs stay dark under a white caller color. TTF print does not.
    -- After Font.drawBox the caller color is white, so print would be white
    -- on white -- a blank mod menu.
    if (cr or 1) + (cg or 1) + (cb or 1) > 2.4 then
      G.setColor(0, 0, 0, ca or 1)
    end
    G.print(text, x or 0, y or 0)
    G.setColor(cr, cg, cb, ca)
    if prev and G.setFont then G.setFont(prev) end
    return Font.width(text)
  end

  function Font.drawCode(code, x, y)
    local ch = ">"
    if code == 0xEE then ch = "v"
    elseif code == 0xEC then ch = "+" end
    return Font.draw(ch, x or 0, y or 0)
  end

  function Font.drawBox(tx, ty, tw, th, fill)
    local G = love and love.graphics
    if not G then return end
    local x, y = (tx or 0) * 8, (ty or 0) * 8
    local w, h = (tw or 1) * 8, (th or 1) * 8
    local cr, cg, cb, ca = 1, 1, 1, 1
    if G.getColor then cr, cg, cb, ca = G.getColor() end
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", x + 1, y + 1, math.max(0, w - 2), math.max(0, h - 2))
    G.setColor(0, 0, 0, 1)
    G.rectangle("line", x + 0.5, y + 0.5, math.max(0, w - 1), math.max(0, h - 1))
    G.setColor(cr, cg, cb, ca)
  end

  -- load becomes a no-op success so ensureManagerFont cannot re-break us
  -- by pointing at the stub Red sheet.
  function Font.load(_data)
    ensureTtf()
  end

  Font._gen3PlainPixel = true
  return Font
end

local function buildFont()
  local real = loadDiskFont()
  if real then
    return armPlainPixelFont(real)
  end

  -- Fallback when Font.lua is missing from the mount: measure + Game3 draw.
  local okG3, Game3 = pcall(require, "src.core.Game3")
  if not okG3 then Game3 = nil end
  local Font = {}

  local function game()
    local g = resolveGame and resolveGame()
    if type(g) == "table" then return g end
    return nil
  end

  function Font.width(text)
    local g = game()
    if not g or type(Game3) ~= "table"
        or type(Game3.textWidth) ~= "function" then
      return #tostring(text or "") * 8
    end
    local ok, w = pcall(function()
      return Game3.textWidth(tostring(text or ""), g:font3WidthTable())
    end)
    if ok and type(w) == "number" then return w end
    return #tostring(text or "") * 8
  end

  function Font.height() return 8 end
  function Font.lineHeight() return 8 end

  function Font.load() end

  function Font.draw(text, x, y)
    local g = game()
    if g and type(g.drawText) == "function" then
      pcall(g.drawText, g, tostring(text or ""), x or 0, y or 0)
      return
    end
    if love and love.graphics and love.graphics.print then
      love.graphics.print(tostring(text or ""), x or 0, y or 0)
    end
  end

  function Font.drawCode(code, x, y)
    -- Gen1 border/cursor codes: approximate with ASCII so menus are usable.
    local ch = ">"
    if type(code) == "number" then
      if code == 0xED or code == 0xEC then ch = ">"
      elseif code == 0xEE then ch = "v"
      else ch = "+" end
    end
    Font.draw(ch, x or 0, y or 0)
  end

  function Font.drawBox(tx, ty, tw, th, fill)
    if not (love and love.graphics) then return end
    local G = love.graphics
    local x, y = (tx or 0) * 8, (ty or 0) * 8
    local w, h = (tw or 1) * 8, (th or 1) * 8
    local cr, cg, cb, ca = 0, 0, 0, 1
    if G.getColor then cr, cg, cb, ca = G.getColor() end
    if fill then
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", x + 1, y + 1, math.max(0, w - 2), math.max(0, h - 2))
    end
    G.setColor(0, 0, 0, 1)
    G.rectangle("line", x + 0.5, y + 0.5, math.max(0, w - 1), math.max(0, h - 1))
    G.setColor(cr, cg, cb, ca)
  end

  return armPlainPixelFont(Font)
end

-- Gen 1's Strings is a function (fmt [, ...]) -> string. Ruby has no
-- localization table under that name; identity + string.format is enough
-- for mods that only use it to mark UI copy.
-- Soft stub: present enough that `require("src.render.TextBox")` (and
-- FieldDefaults / PaletteFX / …) returns a table Gen1-shaped mods can wrap.
--
-- __index rules:
--   1. `new` — special-case: rawset a factory that yields `{ __index = t }`.
--   2. string keys starting with `__` (mod-stamped data like `__freeFlyMount`,
--      `__freeFlyMountScale`, `__freeFlyBird`, `__freeFlyWrapped`, …) —
--      return nil and do NOT rawset. Early reads must stay nil so a later
--      stamp installs a real table/number/bool; caching a no-op function
--      here poisons truthiness and `math.max` / `.def` (free_fly mount bug).
--   3. every other missing key — cache and return `function() return nil end`
--      via rawset. Restores Gen1-shaped method stubbing so
--      `FieldDefaults.field(...)`, wraps, etc. are callable instead of nil.
--
-- Player is NOT a softStub (see buildPlayer); PaletteFX gets an explicit
-- effectiveColors on top of softStub (see buildPaletteFX).
local function softStub(label)
  local M = { _gen3SoftStub = label }
  setmetatable(M, {
    __index = function(t, key)
      if key == "new" then
        local f = function()
          return setmetatable({}, { __index = t })
        end
        rawset(t, key, f)
        return f
      end
      if type(key) == "string" and string.sub(key, 1, 2) == "__" then
        return nil
      end
      local f = function() return nil end
      rawset(t, key, f)
      return f
    end,
  })
  return function() return M end
end

-- ----------------------------------------------------------- src.render.PaletteFX
--
-- SoftStub plus one honest method. DramaticShapes VoxelScene.modeColors does
-- `return PaletteFX.effectiveColors(c)` with no nil fallback; a softStub no-op
-- that returns nil kills the voxel pipeline ("effectiveColors (a nil value)"
-- was the prior crash; a callable that returns nil still blank the atlas).
-- Ruby has no SGB/GBC display-mode remap, so identity is the truthful answer.
local function buildPaletteFX()
  local M = softStub("src.render.PaletteFX")()
  function M.effectiveColors(c)
    return c
  end
  return M
end

-- ----------------------------------------------------------- src.core.Sound
-- SoftStub alone caches playCry as a no-op, so Wilds town talk / follower
-- Sound.playCry(data, species) silently does nothing on Ruby. Bridge name
-- or national keys → Game3:playMonCry(internalId) via resolveBattleSpecies.
-- Busy flag blocks playMonCry's Gen1 Sound.playCry fallback from recursing.
local function buildSound()
  local M = softStub("src.core.Sound")()
  M._gen3SoundHost = true
  function M.playCry(data, species)
    return Gen3Compat.playCryBridge(data, species)
  end
  M._gen3CryBridged = true
  return M
end

-- ----------------------------------------------------------- src.core.GameVersion
-- Honest passthrough (Emerald-accurate). SoftStub made generation() nil and
-- Wilds refused every adapter. Permanent gen3→1 remaps poisoned ModTargets /
-- the mod menu. LIVE host uses brief load-only remap + GameCompat wrap instead.

local function buildGameVersion()
  local loaded = package.loaded["src.core.GameVersion"]
  if type(loaded) == "table" and loaded._gen3GameVersionHost ~= true
      and type(loaded.generation) == "function" then
    return loaded
  end
  local M = {
    _gen3GameVersionHost = true,
    current = "ruby",
    VERSIONS = {
      ruby = { id = "ruby", generation = 3, label = "Ruby" },
    },
    ORDER = { "ruby" },
  }
  function M.get() return M.current end
  function M.set(id)
    if M.VERSIONS[id] then M.current = id end
    return M.current
  end
  function M.generation(id)
    local info = M.VERSIONS[id or M.current]
    return (info and info.generation) or 3
  end
  function M.isGen1(id) return M.generation(id) == 1 end
  function M.isGen2(id) return M.generation(id) == 2 end
  function M.isGen3(id) return M.generation(id) == 3 end
  function M.info(id)
    return M.VERSIONS[id or M.current]
      or { id = M.get(), generation = 3, label = "Ruby" }
  end
  return M
end

local ADAPTERS = {
  ["src.core.Game"] = buildGame,
  ["src.world.Map"] = buildMap,
  ["src.render.GBCFX"] = buildGbcFx,
  ["src.ui.OptionsMenu"] = buildOptionsMenu,
  -- A path rather than a builder: resolve requires it, and Lua's own module
  -- cache then hands the mod THE SAME TABLE Game3:fieldHandleInput requires.
  -- That shared identity is the point -- a wrap installed on the mod's copy
  -- has to be the one the engine calls, which is the lesson the voxel hotkey
  -- taught when a wrap on the facade sat beside the path instead of in it.
  ["src.world.OverworldController"] = "src.world.gen3.OverworldAPI",
  -- served so a Gen 3 mod does not fall through to Gen 1's collision, whose
  -- canMove reads block tables this game does not have
  ["src.world.Collision"] = "src.world.gen3.Collision",
  ["src.ui.Screens"] = buildScreens,
  ["src.ui.OptionRows"] = buildOptionRows,
  ["src.battle.BattleState"] = buildBattleState,
  ["src.world.NPC"] = buildNpc,
  -- Soft stubs (see softStub above): keep Gen1-shaped mods loading on Ruby.
  ["src.render.TextBox"] = buildTextBox,
  ["src.render.Font"] = buildFont,
  ["src.render.PaletteFX"] = buildPaletteFX,
  ["src.pokemon.Pokemon"] = softStub("src.pokemon.Pokemon"),
  ["src.world.Player"] = buildPlayer,
  ["src.world.FieldDefaults"] = softStub("src.world.FieldDefaults"),
  ["src.inventory.ItemEffects"] = softStub("src.inventory.ItemEffects"),
  ["src.ui.PartyMenu"] = buildPartyMenu,
  ["src.world.PikachuFollower"] = buildPikachuFollower,
  ["src.ui.MoveLearnMenu"] = softStub("src.ui.MoveLearnMenu"),
  ["src.core.Sound"] = buildSound,
  -- Chip-channel Music.lua is the Gen 1/2 player. Ruby's songs are MP2K
  -- tracks on Game3, so a mod requiring src.core.Music (HM Anywhere SURF)
  -- must not start a GB chip program.
  ["src.core.Music"] = function()
    local M = softStub("src.core.Music")()
    function M.setSurfing(_, on)
      local g = live()
      if type(g) == "table" and type(g.setSurfing) == "function" then
        pcall(g.setSurfing, g, on)
      elseif type(g) == "table" then
        g.surfing = on and true or nil
      end
    end
    function M.play(_, song)
      local g = live()
      if type(g) == "table" and type(g.playSong) == "function" then
        pcall(g.playSong, g, song)
      end
    end
    return M
  end,
  -- src.core.Strings IS NOT SERVED HERE, and that is the answer, not a gap.
  --
  -- It is the one module a mod asks for that is not Gen 1's at all: the
  -- engine's own text catalog, keyed by the English source string, an identity
  -- function until a catalog is loaded.  Nothing in it reads a cartridge
  -- table, so Hoenn needs no adapter -- it needs the real module.
  --
  -- Two stand-ins have been tried and both were wrong the same way.  A
  -- softStub answered a function for any FIELD read but carried no __call, so
  -- `Strings("QOL TOGGLES")` raised "attempt to call upvalue 'Strings' (a
  -- table value)" on every ui.options.rows hook.  A bare
  -- `function(fmt, ...)` fixes the call and loses the rest: Strings.load,
  -- .active, .lookup, .get and .source stop existing (BattleState and
  -- MomShopping reach for .source BY NAME), and -- the quiet one -- it holds
  -- no catalog, so the `strings` registry merges into data.strings and nothing
  -- on Ruby ever reads it.  A translation mod would register its entries and
  -- see no effect: the failure that looks like success.
  --
  -- Leaving the name unserved makes `serves` say no and the loader's require
  -- gate fall through to the real module, which is what Red and Gold already
  -- get.  Nothing stands in the way: src.core.Strings is absent from
  -- GEN1_ONLY_MODULES and matches no GENERATION_MODULES rule, so neither gate
  -- in src/mods/Loader.lua claims it.  Verified on a live Ruby boot: the
  -- QOL TOGGLES row draws its "12/44 ON" through exactly this call.
  ["src.core.GameVersion"] = buildGameVersion,
}

Gen3Compat.ADAPTERS = ADAPTERS

function Gen3Compat.bind(fn)
  resolveGame = fn
  -- If the engine already raw-required Font before the facade bound,
  -- arm THAT instance too — otherwise QOL still hits encode spam.
  local existing = package.loaded["src.render.Font"]
  if type(existing) == "table" and type(existing.draw) == "function"
      and existing._gen3PlainPixel ~= true then
    armPlainPixelFont(existing)
    existing._gen3PlainPixel = true
  end
end

function Gen3Compat.serves(name)
  return ADAPTERS[name] ~= nil
end

function Gen3Compat.modules()
  local out = {}
  for name in pairs(ADAPTERS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function Gen3Compat.coverage(name)
  local row = COVERAGE[name]
  if not row then return nil end
  local members = {}
  -- warned last, as Gen2Compat does it: a name listed both backed and warned
  -- is present and degraded, and the weaker claim is the safe one to publish
  for _, status in ipairs({ "backed", "absent", "warned" }) do
    for _, member in ipairs(words(row[status])) do
      members[member] = status
    end
  end
  local notes = {}
  for key, value in pairs(row.notes or {}) do notes[key] = value end
  return { module = name, kind = row.kind, target = row.target,
           members = members, notes = notes }
end

function Gen3Compat.memberStatus(name, member)
  local row = Gen3Compat.coverage(name)
  return row and row.members[member] or nil
end

-- The one entry point the Loader calls. `modId` is attribution only.
function Gen3Compat.resolve(name, modId)
  local spec = ADAPTERS[name]
  if not spec then return nil end
  local module = built[name]
  if not module then
    module = type(spec) == "string" and require(spec) or spec()
    built[name] = module
  end
  if modId then
    local ids = claimants[name]
    if not ids then ids = {} claimants[name] = ids end
    local seen = false
    for _, id in ipairs(ids) do if id == modId then seen = true break end end
    if not seen then ids[#ids + 1] = modId end
  end
  return module
end



-- ----------------------------------------------------------- Wilds guest park
-- Side-channel only. Never writes ow.entities / CAST_KEYS / trackInserts.

function Gen3Compat.isModOwGuest(e)
  if type(e) ~= "table" then return false end
  if e._modOwGuest or e._wildsGoldGuest then return true end
  if e.overworldWildSpawn or e._owwildEntity then return true end
  if type(e.pose) == "function" and type(e.draw) == "function"
      and (e.species ~= nil or e.wildSpecies ~= nil) then
    return true
  end
  return false
end

--- Resolve a Wilds species key (name or id) to Gen3 NATIONAL dex for sheets.
-- speciesRow/nationalDexOf only index by internal id; Wilds uses "ZIGZAGOON".
-- Static Hoenn name → national dex for sheets when pokemon.byIndex is not
-- ready yet (spawn-before-data). Covers common early-route / water guests so
-- we never leave SPRITE_OW_WILD_FALLBACK / PLACEHOLDER when a follower PNG
-- exists under followsprites_runtime/<dex>-normal.png.
Gen3Compat.HOENN_NATIONAL = {
  TREECKO = 252, GROVYLE = 253, SCEPTILE = 254,
  TORCHIC = 255, COMBUSKEN = 256, BLAZIKEN = 257,
  MUDKIP = 258, MARSHTOMP = 259, SWAMPERT = 260,
  POOCHYENA = 261, MIGHTYENA = 262,
  ZIGZAGOON = 263, LINOONE = 264,
  WURMPLE = 265, SILCOON = 266, BEAUTIFLY = 267,
  CASCOON = 268, DUSTOX = 269,
  LOTAD = 270, LOMBRE = 271, LUDICOLO = 272,
  SEEDOT = 273, NUZLEAF = 274, SHIFTRY = 275,
  TAILLOW = 276, SWELLOW = 277,
  WINGULL = 278, PELIPPER = 279,
  RALTS = 280, KIRLIA = 281, GARDEVOIR = 282, GALLADE = 475,
  SURSKIT = 283, MASQUERAIN = 284,
  SHROOMISH = 285, BRELOOM = 286,
  SLAKOTH = 287, VIGOROTH = 288, SLAKING = 289,
  NINCADA = 290, NINJASK = 291, SHEDINJA = 292,
  WHISMUR = 293, LOUDRED = 294, EXPLOUD = 295,
  MAKUHITA = 296, HARIYAMA = 297,
  AZURILL = 298, NOSEPASS = 299, SKITTY = 300, DELCATTY = 301,
  SABLEYE = 302, MAWILE = 303,
  ARON = 304, LAIRON = 305, AGGRON = 306,
  MEDITITE = 307, MEDICHAM = 308,
  ELECTRIKE = 309, MANECTRIC = 310,
  PLUSLE = 311, MINUN = 312,
  VOLBEAT = 313, ILLUMISE = 314,
  ROSELIA = 315, GULPIN = 316, SWALOT = 317,
  CARVANHA = 318, SHARPEDO = 319,
  WAILMER = 320, WAILORD = 321,
  NUMEL = 322, CAMERUPT = 323, TORKOAL = 324,
  SPOINK = 325, GRUMPIG = 326, SPINDA = 327,
  TRAPINCH = 328, VIBRAVA = 329, FLYGON = 330,
  CACNEA = 331, CACTURNE = 332,
  SWABLU = 333, ALTARIA = 334,
  ZANGOOSE = 335, SEVIPER = 336,
  LUNATONE = 337, SOLROCK = 338,
  BARBOACH = 339, WHISCASH = 340,
  CORPHISH = 341, CRAWDAUNT = 342,
  BALTOY = 343, CLAYDOL = 344,
  LILEEP = 345, CRADILY = 346,
  ANORITH = 347, ARMALDO = 348,
  FEEBAS = 349, MILOTIC = 350,
  CASTFORM = 351, KECLEON = 352,
  SHUPPET = 353, BANETTE = 354,
  DUSKULL = 355, DUSCLOPS = 356, DUSKNOIR = 477,
  TROPIUS = 357, CHIMECHO = 358,
  ABSOL = 359, WYNAUT = 360,
  SNORUNT = 361, GLALIE = 362, FROSLASS = 478,
  SPHEAL = 363, SEALEO = 364, WALREIN = 365,
  CLAMPERL = 366, HUNTAIL = 367, GOREBYSS = 368,
  RELICANTH = 369, LUVDISC = 370,
  BAGON = 371, SHELGON = 372, SALAMENCE = 373,
  BELDUM = 374, METANG = 375, METAGROSS = 376,
  REGIROCK = 377, REGICE = 378, REGISTEEL = 379,
  LATIAS = 380, LATIOS = 381,
  KYOGRE = 382, GROUDON = 383, RAYQUAZA = 384,
  JIRACHI = 385, DEOXYS = 386,
}

function Gen3Compat.nationalDexOfSpecies(game, species)
  if species == nil or type(game) ~= "table" then return nil end
  local n = tonumber(species)
  if n then
    if type(game.nationalDexOf) == "function" then
      local ok, dex = pcall(game.nationalDexOf, game, n)
      if ok and tonumber(dex) then return tonumber(dex) end
    end
    return n
  end
  if type(species) ~= "string" or species == "" then return nil end
  local key = species:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
  local Game3 = package.loaded["src.core.Game3"]
  local const = (type(game["SPECIES_" .. key]) == "number" and game["SPECIES_" .. key])
    or (Game3 and type(Game3["SPECIES_" .. key]) == "number" and Game3["SPECIES_" .. key])
  if type(const) == "number" then
    if type(game.nationalDexOf) == "function" then
      local ok, dex = pcall(game.nationalDexOf, game, const)
      if ok and tonumber(dex) then return tonumber(dex) end
    end
    -- Do NOT return `const`: Gen3 SPECIES_* are INTERNAL Ruby ids
    -- (ZIGZAGOON=288 ≠ national 263). Fall through to byIndex / HOENN_NATIONAL.
  end
  local poke = game.data and game.data.pokemon
  local function fromRow(row)
    if type(row) ~= "table" then return nil end
    return tonumber(row.nationalDex or row.dex)
  end
  if type(poke) == "table" then
    local hit = fromRow(poke[key] or poke[species] or poke[key:lower()])
    if hit then return hit end
    local byIndex = poke.byIndex
    if type(byIndex) == "table" then
      for _, row in pairs(byIndex) do
        if type(row) == "table" and type(row.name) == "string" then
          local rn = row.name:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
          if rn == key then
            local d = fromRow(row)
            if d then return d end
          end
        end
      end
    end
    local byName = poke.byName
    if type(byName) == "table" then
      local d = fromRow(byName[key] or byName[species])
      if d then return d end
    end
  end
  local g3 = game.data and game.data.gen3Pokemon
  if type(g3) == "table" then
    local d = fromRow(g3[key] or g3[species])
    if d then return d end
  end
  -- Last resort: static Hoenn map so sheets bind even before pokemon data.
  local static = Gen3Compat.HOENN_NATIONAL and Gen3Compat.HOENN_NATIONAL[key]
  if tonumber(static) then return tonumber(static) end
  return nil
end

--- Resolve Wilds species key to Gen3 INTERNAL species id for makeMon/startWildBattle.
function Gen3Compat.resolveBattleSpecies(game, species)
  if species == nil then return nil end
  local n = tonumber(species)
  if n then
    -- Already an internal id, or a national dex mistaken for one.
    if type(game) == "table" then
      local byIndex = game.data and game.data.pokemon and game.data.pokemon.byIndex
      if type(byIndex) == "table" and type(byIndex[n]) == "table" then
        return n
      end
      -- National dex → internal: scan byIndex.nationalDex.
      if type(byIndex) == "table" then
        for id, row in pairs(byIndex) do
          if type(row) == "table" and tonumber(row.nationalDex) == n then
            return tonumber(id) or id
          end
        end
      end
    end
    return n
  end
  if type(species) ~= "string" or species == "" then return species end
  local key = species:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
  local Game3 = package.loaded["src.core.Game3"]
  local const = (type(game) == "table" and type(game["SPECIES_" .. key]) == "number" and game["SPECIES_" .. key])
    or (Game3 and type(Game3["SPECIES_" .. key]) == "number" and Game3["SPECIES_" .. key])
  if type(const) == "number" then return const end
  if type(game) ~= "table" then return species end
  local poke = game.data and game.data.pokemon
  if type(poke) == "table" then
    local row = poke[key] or poke[species]
    if type(row) == "table" then
      local id = tonumber(row.id or row.index or row.species)
      if id then return id end
    end
    local byIndex = poke.byIndex
    if type(byIndex) == "table" then
      for id, row in pairs(byIndex) do
        if type(row) == "table" and type(row.name) == "string" then
          local rn = row.name:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
          if rn == key then return tonumber(id) or id end
        end
      end
      -- Match via national dex from HOENN_NATIONAL when name walk missed.
      local nat = Gen3Compat.HOENN_NATIONAL and Gen3Compat.HOENN_NATIONAL[key]
      if tonumber(nat) then
        for id, row in pairs(byIndex) do
          if type(row) == "table" and tonumber(row.nationalDex) == tonumber(nat) then
            return tonumber(id) or id
          end
        end
      end
    end
    local byName = poke.byName
    if type(byName) == "table" then
      local row = byName[key] or byName[species]
      if type(row) == "table" then
        local id = tonumber(row.id or row.index or row.species)
        if id then return id end
      elseif type(byName[key]) == "number" then
        return byName[key]
      end
    end
  end
  return species
end

--- Stamp a guest Entity with the runtime follow sheet (16x96) so flat/voxel
-- draw and Wilds SpriteRenderer leave FALLBACK_ID / PLACEHOLDER behind.
-- Engine-only; does not edit overworld_wild_spawns (SpeciesAssets has no
-- Hoenn names). Sheets are full RGBA; trueColor=true. Clears
-- blackFallbackSprite / usingFallback so pose() returns the colored sprite
-- before the first flat draw (water/? guests included).
local function _wildsIsFallbackId(id)
  if type(id) ~= "string" or id == "" then return false end
  local u = id:upper()
  return u:find("FALLBACK", 1, true) ~= nil
    or u:find("PLACEHOLDER", 1, true) ~= nil
    or u:find("MISSING", 1, true) ~= nil
end

local function _wildsIsFallbackPath(p)
  if type(p) ~= "string" or p == "" then return true end
  local u = p:upper()
  return u:find("FALLBACK", 1, true) ~= nil
    or u:find("PLACEHOLDER", 1, true) ~= nil
    or u:find("MISSING", 1, true) ~= nil
    or u:find("POKEMON_MISSING", 1, true) ~= nil
end

local function _wildsGoodDef(def)
  if type(def) ~= "table" then return false end
  local img = def.image or def.path
  return type(img) == "string" and img ~= "" and not _wildsIsFallbackPath(img)
end

function Gen3Compat.refreshGuestSprite(game, entity)
  if type(game) ~= "table" or type(entity) ~= "table" then return false end
  local mod = Gen3Compat._wildsBindMod
  local exports = mod and (mod.exports or mod) or nil
  local render = exports and (exports.render or mod._owwildRender or mod.render)
  if type(render) ~= "table" and type(exports) == "table" then
    local logic = exports.logic or mod._owwildLogic or mod.logic
    render = logic and logic.render
  end
  local sheets = render and render.runtimeSheets
  -- A FOLLOWER TRAILER NAMES ITS SPECIES SOMEWHERE ELSE.
  --
  -- Wilds' wild spawns carry `species` ("MARILL") and stamp correctly.  Its
  -- follower trailers carry NONE of the usual fields -- species, speciesId,
  -- dexId, nationalDex and enhancedDexId are all nil -- and record the mon
  -- only as `_wildsFollowerSpecies`, because the trailer reuses one
  -- registered sprite slot (Constants.SPRITE_ID = "SPRITE_PIKACHU") and
  -- swaps the image behind it per species.
  --
  -- So this function found no dex, returned false, and every follower kept
  -- whatever that shared slot last held: Groudon, Rayquaza, Sceptile,
  -- Tentacool and Zigzagoon all walked around as the same sprite.
  local dex = Gen3Compat.nationalDexOfSpecies(game, entity.species)
  if not dex then
    local followerSpecies = rawget(entity, "_wildsFollowerSpecies")
    if followerSpecies ~= nil then
      dex = Gen3Compat.nationalDexOfSpecies(game, followerSpecies)
    end
  end
  if not dex then
    dex = tonumber(entity.enhancedDexId) or tonumber(entity.dexId)
      or tonumber(entity.nationalDex) or tonumber(entity.speciesId)
  end
  if not dex and type(entity.species) == "number" then
    dex = tonumber(entity.species)
  end
  if not dex then
    local fs = rawget(entity, "_wildsFollowerSpecies")
    if type(fs) == "number" then dex = fs end
  end
  if not dex then
    if not Gen3Compat._wildsMissingDexLogged then
      Gen3Compat._wildsMissingDexLogged = {}
    end
    local sk = tostring(entity.species or "?")
    if not Gen3Compat._wildsMissingDexLogged[sk] then
      Gen3Compat._wildsMissingDexLogged[sk] = true
      local Logger = package.loaded["src.core.Logger"]
      if Logger and Logger.warn then
        pcall(Logger.warn, "gen3 wilds host: no national dex for species %s (placeholder risk)", sk)
      end
    end
    return false
  end

  game.data = game.data or {}
  local sprites = game.data.sprites
  if type(sprites) ~= "table" then
    sprites = {}
    game.data.sprites = sprites
  end
  local dexId = "SPRITE_OW_WILD_" .. tostring(dex)
  local nameKey = nil
  if type(entity.species) == "string" and entity.species ~= "" then
    nameKey = entity.species:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
  end
  local nameId = nameKey and ("SPRITE_OW_WILD_" .. nameKey) or nil

  -- Prefer a non-fallback def; skip stale FALLBACK/? rows in data.sprites.
  -- Try every sheet path: bound sprites → runtimeSheets.spriteDef →
  -- resolveAssetPath / resolvePath → hasSheet → synthetic followsprites path.
  local def = nil
  if _wildsGoodDef(sprites[dexId]) then def = sprites[dexId] end
  if not def and nameId and _wildsGoodDef(sprites[nameId]) then def = sprites[nameId] end
  local function trySheetDef(variant)
    if type(sheets) ~= "table" then return nil end
    if type(sheets.isReady) == "function" and not sheets:isReady() then
      if type(sheets.load) == "function" then pcall(function() sheets:load() end) end
    end
    -- PREFER THE MOD'S HIGHER-RESOLUTION SHEET.
    --
    -- Wilds resolves to generated/followsprites_runtime, a 16px downscale
    -- that leaves Hoenn species unrecognisable.  enhanced_overworld carries
    -- the same species at 32px (64px for some) with directional frames.
    --
    -- Chosen HERE, where the record is built, because this function reruns
    -- every tick: upgrading the record afterwards was overwritten on the
    -- next frame.  Only ever taken when the file is present, so a species
    -- without the better art keeps exactly what it had.
    if (variant == nil or variant == "normal")
        and love and love.filesystem and love.filesystem.getInfo then
      local hi = ("mods/overworld_wild_spawns/assets/enhanced_overworld/"
        .. "followsprites/%03d-b-n.png"):format(dex)
      local info = love.filesystem.getInfo(hi)
      if info then
        local okI, img = pcall(love.graphics.newImage, hi)
        if okI and img then
          local iw, ih = img:getDimensions()
          local cell = math.floor((iw or 0) / 4)
          if cell >= 16 and ih and ih >= cell * 2 then
            return {
              id = dexId,
              image = hi,
              path = hi,
              frames = math.floor(ih / cell),
              frameCount = math.floor(ih / cell),
              width = cell,
              height = cell,
              walker = true,
              trueColor = true,
            }
          end
        end
      end
    end
    if type(sheets.spriteDef) == "function" then
      local ok, got = pcall(sheets.spriteDef, sheets, dex, variant or "normal", dexId)
      if ok and _wildsGoodDef(got) then return got end
    end
    -- Path-only fallbacks when spriteDef shape differs across Wilds builds.
    local path = nil
    if type(sheets.resolveAssetPath) == "function" then
      local okP, p = pcall(sheets.resolveAssetPath, sheets, dex, variant or "normal")
      if okP and type(p) == "string" and p ~= "" then path = p end
    end
    if not path and type(sheets.resolvePath) == "function" then
      local okP, p = pcall(sheets.resolvePath, sheets, dex, variant or "normal")
      if okP and type(p) == "string" and p ~= "" then path = p end
    end
    if path and not _wildsIsFallbackPath(path) then
      return {
        id = dexId,
        image = path,
        path = path,
        frames = 6,
        frameCount = 6,
        width = 16,
        height = 16,
        walker = true,
        trueColor = true,
      }
    end
    return nil
  end
  if not def then def = trySheetDef("normal") end
  if not def then def = trySheetDef("shiny") end  -- last-ditch; better than ?
  -- Synthetic AppData / packaged followsprite path when sheets API is quiet
  -- but the PNG is known to exist for this national dex.
  -- THE HIGHER-RESOLUTION SHEET FIRST.
  --
  -- The candidates below are the 16px downscale, and the first one is taken
  -- WITHOUT checking it exists -- which is how every Hoenn guest ended up an
  -- unrecognisable blob.  enhanced_overworld holds the same species at 32px
  -- (64px for some) with directional frames, so try it first and only when
  -- the file is really there; cell size is read off the image, never assumed,
  -- because it differs per species.
  if not def and dex and love and love.filesystem and love.filesystem.getInfo then
    local hi = ("mods/overworld_wild_spawns/assets/enhanced_overworld/"
      .. "followsprites/%03d-b-n.png"):format(tonumber(dex) or 0)
    if love.filesystem.getInfo(hi) then
      local okI, img = pcall(love.graphics.newImage, hi)
      if okI and img then
        local iw, ih = img:getDimensions()
        local cell = math.floor((iw or 0) / 4)
        if cell >= 16 and ih and ih >= cell * 2 then
          def = {
            id = dexId,
            image = hi,
            path = hi,
            frames = math.floor(ih / cell),
            frameCount = math.floor(ih / cell),
            width = cell,
            height = cell,
            walker = true,
            trueColor = true,
          }
        end
      end
    end
  end
  if not def and dex then
    local pad = string.format("%03d", tonumber(dex) or 0)
    local candidates = {
      "mods/overworld_wild_spawns/assets/generated/followsprites_runtime/"
        .. pad .. "-normal.png",
      "mods/overworld_wild_spawns/assets/generated/followsprites_runtime/"
        .. tostring(dex) .. "-normal.png",
      "assets/generated/followsprites_runtime/" .. pad .. "-normal.png",
      "assets/generated/followsprites_runtime/" .. tostring(dex) .. "-normal.png",
    }
    for _, rel in ipairs(candidates) do
      if type(rel) == "string" and not _wildsIsFallbackPath(rel) then
        def = {
          id = dexId,
          image = rel,
          path = rel,
          frames = 6,
          frameCount = 6,
          width = 16,
          height = 16,
          walker = true,
          trueColor = true,
        }
        break
      end
    end
  end
  if not _wildsGoodDef(def) then
    -- Log once per species so Raymond can see which guests still fail.
    Gen3Compat._wildsRefreshFailLog = Gen3Compat._wildsRefreshFailLog or {}
    local failKey = tostring(entity.species or dex or "?")
    if not Gen3Compat._wildsRefreshFailLog[failKey] then
      Gen3Compat._wildsRefreshFailLog[failKey] = true
      local Logger = package.loaded["src.core.Logger"]
      if Logger and Logger.warn then
        pcall(Logger.warn,
          "gen3 wilds host: refreshGuestSprite FAILED species=%s dex=%s (no follower sheet)",
          tostring(entity.species), tostring(dex))
      end
    end
    return false
  end
  local image = def.image or def.path

  local function put(id)
    if type(id) ~= "string" or id == "" then return end
    local existing = sprites[id]
    -- Overwrite missing OR fallback OR non-trueColor stubs so water/Hoenn
    -- guests leave SPRITE_OW_WILD_FALLBACK / PLACEHOLDER before first draw.
    if _wildsGoodDef(existing) and existing.trueColor == true
        and (existing.image == image or existing.path == image) then
      return
    end
    sprites[id] = {
      id = id,
      image = image,
      path = def.path or image,
      frames = tonumber(def.frames) or tonumber(def.frameCount) or 6,
      frameCount = tonumber(def.frameCount) or tonumber(def.frames) or 6,
      width = tonumber(def.width) or tonumber(def.frameWidth) or 16,
      height = tonumber(def.height) or tonumber(def.frameHeight) or 16,
      walker = true,
      trueColor = true,
    }
  end
  put(dexId)
  if nameId then put(nameId) end
  if render and type(render.speciesSpriteIds) == "table" then
    local idMap = render.speciesSpriteIds
    local function setMap(key, val)
      if key == nil or val == nil then return end
      local cur = idMap[key]
      if cur == nil or _wildsIsFallbackId(tostring(cur)) then
        idMap[key] = val
      end
    end
    setMap(dex, dexId)
    setMap(tostring(dex), dexId)
    if nameKey then
      setMap(nameKey, nameId or dexId)
      setMap(entity.species, nameId or dexId)
      setMap(nameKey:lower(), nameId or dexId)
    end
  end

  local stamped = sprites[nameId or dexId] or sprites[dexId] or def
  if type(stamped) == "table" then
    stamped.imageObj = nil
    stamped._owGuestQuad = nil
    for k in pairs(stamped) do
      if type(k) == "string" and k:find("^_owGuestQuad", 1) then
        stamped[k] = nil
      end
    end
    stamped.trueColor = true
    stamped.image = image
    stamped.path = stamped.path or image
  end

  entity.spriteId = nameId or dexId
  entity.usingFallback = false
  entity.blackFallbackSprite = nil
  entity.enhancedDexId = dex
  entity.pendingSpriteDef = stamped
  entity.spriteDef = stamped
  entity.entityPhase = "NATIVE_SHEET_LOADED"

  local function applyToSpr(spr)
    if type(spr) ~= "table" then return end
    if type(spr.def) ~= "table" then
      spr.def = {
        id = entity.spriteId,
        image = image,
        path = stamped.path or image,
        frames = stamped.frames or 6,
        frameCount = stamped.frameCount or stamped.frames or 6,
        width = stamped.width or 16,
        height = stamped.height or 16,
        walker = true,
        trueColor = true,
      }
      return
    end
    spr.def.image = image
    spr.def.path = stamped.path or image
    spr.def.frames = stamped.frames or spr.def.frames or 6
    spr.def.frameCount = stamped.frameCount or spr.def.frameCount or spr.def.frames
    spr.def.walker = true
    spr.def.trueColor = true
    spr.def.id = entity.spriteId
    spr.def.width = stamped.width or spr.def.width or 16
    spr.def.height = stamped.height or spr.def.height or 16
    spr.def.imageObj = nil
    spr.image = nil
    spr._image = nil
    spr.baked = nil
  end
  applyToSpr(entity.sprite)
  applyToSpr(entity.legacySprite)

  -- Rebuild SpriteRenderer when available so voxel billboards leave FALLBACK.
  do
    local okSR, SpriteRenderer = pcall(require, "src.render.SpriteRenderer")
    if okSR and type(SpriteRenderer) == "table" and type(SpriteRenderer.new) == "function" then
      local drawDef = {
        id = entity.spriteId,
        image = image,
        path = stamped.path or image,
        frames = tonumber(stamped.frames) or 6,
        frameCount = tonumber(stamped.frameCount) or tonumber(stamped.frames) or 6,
        walker = true,
        trueColor = true,
        width = tonumber(stamped.width) or 16,
        height = tonumber(stamped.height) or 16,
      }
      local okNew, newSpr = pcall(SpriteRenderer.new, drawDef, entity.spawnId or entity.id)
      if okNew and type(newSpr) == "table" then
        local old = entity.sprite
        if type(old) == "table" then
          newSpr.facing = old.facing or entity.facing
          newSpr.phase = old.phase
          newSpr.flip = old.flip
          newSpr.x = old.x
          newSpr.y = old.y
        end
        entity.sprite = newSpr
        entity.legacySprite = newSpr
      end
    end
  end

  return true
end

--- Re-stamp parked / live Wilds guests onto colored follower sheets.
-- Returns coloredCount, fallbackLeft, stampedTotal.
function Gen3Compat.restampGuestSprites(game)
  if type(game) ~= "table" then return 0, 0, 0 end
  local colored, fallbackLeft, stamped = 0, 0, 0
  local seen = {}
  local function consider(ent)
    if type(ent) ~= "table" or seen[ent] then return end
    seen[ent] = true
    local ok = Gen3Compat.refreshGuestSprite(game, ent)
    if ok then
      stamped = stamped + 1
      local sid = ent.spriteId
      local path = (ent.spriteDef and (ent.spriteDef.image or ent.spriteDef.path))
        or (ent.sprite and ent.sprite.def and (ent.sprite.def.image or ent.sprite.def.path))
      if ent.usingFallback or _wildsIsFallbackId(tostring(sid or ""))
          or _wildsIsFallbackPath(path) then
        fallbackLeft = fallbackLeft + 1
      else
        colored = colored + 1
      end
    else
      fallbackLeft = fallbackLeft + 1
    end
  end
  local mod = Gen3Compat._wildsBindMod
  local exports = mod and (mod.exports or mod) or nil
  local logic = exports and (exports.logic or mod._owwildLogic or mod.logic)
  if type(logic) == "table" and type(logic.entities) == "table" then
    for _, ent in pairs(logic.entities) do consider(ent) end
  end
  local guests = game._modOwGuests
  if type(guests) == "table" then
    for _, ent in ipairs(guests) do consider(ent) end
  end
  return colored, fallbackLeft, stamped
end

-- THE DUPLICATE FOLLOWERS THAT APPEAR WHEN YOU LEAVE A MAP AND COME BACK.
--
-- Wilds' trailers are parked on game._modOwGuests so Game3's draw and the
-- ephemeral pipeline can see them, and that list is drawn INDEPENDENTLY of
-- ow.entities.  Nothing pruned it on a map change: the mod rebuilt its
-- trailers for the new map and parked them again, while the previous map's
-- entities stayed in the list and kept drawing.
--
-- Measured across five map changes with five followers: ow.entities held a
-- correct 5 throughout, while the parked list went 5 -> 10 -> 15 -> 20 ->
-- 25 -> 30.  Every one of those was a sprite on screen.
--
-- Pruned on the map id CHANGING rather than every tick: a guest legitimately
-- sits in the list for a frame or two before the mod inserts it into
-- ow.entities, and pruning continuously would race that.
-- THE MOD PICKS THE FRAME, INCLUDING WHICH WAY THE MON IS FACING.
--
-- A follower sheet is 16x96: six 16x16 frames.  Game3's guest draw cropped
-- row `phase % 6` and left a comment admitting it guessed -- "facing rows:
-- down/left/right/up ~= 0..3 in many follower strips" -- so every follower
-- walked with the same front-facing pair no matter which way it went.
--
-- Wilds already owns that mapping: AnimatedSprites:getImage(species, variant)
-- and :getQuad(species, anim, direction, frame, variant) answer per DIRECTION
-- off its own atlas.  Ask it rather than asserting a row here; guessing the
-- layout from the sheet is exactly how a follower ends up facing the wrong
-- way on some species and right on others.
--
-- Answers nil whenever anything is missing, so the caller keeps its existing
-- behaviour rather than losing the sprite.
local GEN3_FACING_TO_DIR = {
  north = "up", up = "up", back = "up",
  south = "down", down = "down", front = "down",
  west = "left", left = "left",
  east = "right", right = "right",
}

function Gen3Compat.wildsGuestFrame(game, entity, facing, phase)
  if type(game) ~= "table" or type(entity) ~= "table" then return nil end
  local mod = Gen3Compat._wildsBindMod
  local exports = mod and (mod.exports or mod) or nil
  local an = exports and exports.animated or nil
  if type(an) ~= "table" or type(an.getImage) ~= "function"
      or type(an.getQuad) ~= "function" then
    return nil
  end
  if type(an.isReady) == "function" then
    local okR, ready = pcall(an.isReady, an)
    if not okR or not ready then return nil end
  end
  local dex = Gen3Compat.nationalDexOfSpecies(game, entity.species)
  if not dex then
    local fs = rawget(entity, "_wildsFollowerSpecies")
    if fs ~= nil then dex = Gen3Compat.nationalDexOfSpecies(game, fs) end
    if not dex and type(fs) == "number" then dex = fs end
  end
  if not dex then return nil end
  local dir = GEN3_FACING_TO_DIR[tostring(facing or "down"):lower()] or "down"
  -- the mod indexes frames from 1; phase is the engine's 0-based walk beat
  local n = tonumber(phase) or 0
  local frameIndex = math.floor(n) % 2 + 1
  local okI, img = pcall(an.getImage, an, dex, nil)
  if not okI or not img then return nil end
  local okQ, quad = pcall(an.getQuad, an, dex, "walk", dir, frameIndex, nil)
  if not okQ or not quad then return nil end
  return img, quad
end

function Gen3Compat.pruneStaleGuests(game, ow)
  if type(game) ~= "table" then return 0 end
  local guests = rawget(game, "_modOwGuests")
  if type(guests) ~= "table" then return 0 end
  local mapId = game.map and game.map.id
  local mapChanged = game._gen3GuestMapId ~= mapId
  game._gen3GuestMapId = mapId
  local live = {}
  local ents = type(ow) == "table" and ow.entities or nil
  if type(ents) == "table" then
    for _, e in pairs(ents) do
      if type(e) == "table" then live[e] = true end
    end
  end
  local logic = nil
  do
    local mod = Gen3Compat._wildsBindMod
    local exports = mod and (mod.exports or mod) or nil
    logic = exports and exports.logic or nil
  end
  if type(logic) == "table" and type(logic.entities) == "table" then
    for _, e in pairs(logic.entities) do
      if type(e) == "table" then live[e] = true end
    end
  end
  -- ORPHANS ARE DROPPED EVEN WITHOUT A MAP CHANGE.
  --
  -- Dismissing a follower takes it out of the mod's entity list but leaves
  -- it parked here, and this list draws on its own -- so the pack detached
  -- and sat on the ground forever.  A map change was too rare a trigger.
  --
  -- A short grace period rather than dropping immediately: a guest
  -- legitimately sits in this list for a frame or two after being parked and
  -- before the mod inserts it into ow.entities, and dropping it in that
  -- window would delete a follower as it spawned.
  local GRACE = 30
  -- give each parked guest the better art once, where the mod has some
  for i = 1, #guests do
    local g = guests[i]
    if type(g) == "table" then pcall(Gen3Compat.upgradeGuestArt, game, g) end
  end
  local dropped = 0
  for i = #guests, 1, -1 do
    local g = guests[i]
    if type(g) ~= "table" then
      table.remove(guests, i)
      dropped = dropped + 1
    elseif live[g] then
      g._gen3OrphanTicks = nil
    else
      local n = (g._gen3OrphanTicks or 0) + 1
      g._gen3OrphanTicks = n
      if mapChanged or n >= GRACE then
        table.remove(guests, i)
        dropped = dropped + 1
        -- hide it as well: something else may still hold the reference
        g.hidden = true
        g.invisible = true
      end
    end
  end
  return dropped
end

function Gen3Compat.parkModOwGuest(game, entity)
  if not game or type(entity) ~= "table" then return false end
  entity._modOwGuest = true
  local guests = game._modOwGuests
  if type(guests) ~= "table" then
    guests = {}
    game._modOwGuests = guests
  end
  local already = false
  for _, g in ipairs(guests) do
    if g == entity then already = true; break end
    if entity.id and g.id and g.id == entity.id then already = true; break end
  end
  if not already then
    guests[#guests + 1] = entity
  end
  -- Post-attach: stamp runtime follow sheet before first draw (FALLBACK/?
  -- may already be bound for water/Hoenn species).
  local ok = Gen3Compat.refreshGuestSprite(game, entity)
  if not ok then
    -- Keep the collect restamp loop alive for this late guest.
    game._wildsGuestsFullyColored = nil
  end
  return true
end

function Gen3Compat.unparkModOwGuest(game, entity)
  if not game or type(entity) ~= "table" then return end
  local guests = game._modOwGuests
  if type(guests) ~= "table" then return end
  for i = #guests, 1, -1 do
    local g = guests[i]
    if g == entity or (entity.id and g and g.id and g.id == entity.id) then
      table.remove(guests, i)
    end
  end
end

-- Wilds decides a map's encounter SURFACE in lib/surface.lua, and its
-- cave test is Kanto-shaped:
--
--   Surface.isIndoorEncounterMap reads game.data.field.indoorEncounters
--   ("map index >= firstIndoorMap and tileset ~= FOREST").  Ruby has no
--   data.field at all, so it falls back to matching the map's TILESET NAME
--   against CAVERN/CEMETERY/FACILITY/SHIP/MANSION, or its ID against
--   "CAVE"/"MT_"/"DIGLETT"/... -- Kanto's own spellings.
--
-- Hoenn answers neither.  Granite Cave 1F is id "g24_7" on tileset
-- "pair_13", so the test returns false, Surface.resolve falls through to
-- "encounter table present but no grass/cave/water tiles", tileMode lands on
-- "none", and no cave on the continent ever gets a spawn.  The map view DOES
-- carry the truth (def.mapType = 4 UNDERGROUND, def.outdoor = false); the
-- mod just has no Gen 3 spelling to read it with.
--
-- Wrapped here rather than patched in the mod, so the mod file stays
-- byte-identical and keeps running on the Gen 1/2 engines it shipped for.
-- The original is tried FIRST: a map Kanto's own rule accepts is still
-- accepted, and this only answers where that rule has nothing to say.
local GEN3_INDOOR_ENCOUNTER_TYPES = {
  [4] = true,   -- MAP_TYPE_UNDERGROUND: the caves
  [5] = true,   -- MAP_TYPE_UNDERWATER
  [8] = true,   -- MAP_TYPE_INDOOR: New Mauville, the Abandoned Ship
  [9] = true,   -- MAP_TYPE_SECRET_BASE
}

-- THE OPTIONS LINK THAT OPENED NOTHING.
--
-- A mod's OPTIONS row activates with `mod.ui.push(game, screenId)`, and
-- mod.ui is the ENGINE's src.ui.ModUI (Loader hands the real module to every
-- mod).  ModUI.push calls require("src.ui.Screens") through the engine's own
-- require, so it gets Gen 1's Screens, not the Gen 3 facade the sandbox
-- serves -- and Gen 1's push does `game.stack:push(inst)` and nothing else.
--
-- On Ruby that half-works, which is why it looked dead rather than broken:
-- game.stack is real (the mod manager uses it), so the push SUCCEEDS and the
-- instance lands on the stack.  But Ruby's menus are Game3 FIELD states; the
-- stack is only stepped and drawn while `field.kind == "mods"`, which only
-- Game3:openModScreen sets.  So the screen was pushed, never stepped, never
-- drawn, and the row read as doing nothing at all.
--
-- Routing ModUI.push into the facade fixes every mod's OPEN row at once: the
-- facade resolves the factory from loader.content.screens (where Wilds and
-- qol_toggles both register) and opens it through openModScreen, on the same
-- StateStack + letterbox rails the mod manager already uses.
function Gen3Compat.armModUiPush()
  local ok, ModUI = pcall(require, "src.ui.ModUI")
  if not ok or type(ModUI) ~= "table" then return false, "no ModUI" end
  if ModUI._gen3PushWrapped then return true, "already" end
  local orig = ModUI.push
  if type(orig) ~= "function" then return false, "no push" end
  ModUI._gen3PushWrapped = true
  -- buildScreens is lazy -- it only runs when a mod first requires
  -- src.ui.Screens -- and arming can happen before any mod has.  Build it now
  -- so the wrap below has something to route into.
  if type(gen3ScreensFacade) ~= "table" then pcall(buildScreens) end
  function ModUI.push(game, id, ...)
    -- Only a Game3 target is ours; a Gen 1/2 boot keeps the original path.
    if type(game) == "table" and type(game.openModScreen) == "function"
        and type(gen3ScreensFacade) == "table"
        and type(gen3ScreensFacade.push) == "function" then
      return gen3ScreensFacade.push(game, id, ...)
    end
    return orig(game, id, ...)
  end
  return true, "armed"
end

function Gen3Compat.armWildsSurface(exports)
  if type(exports) ~= "table" then return false, "no exports" end
  local lib = exports.lib
  if type(lib) ~= "table" or type(lib.require) ~= "function" then
    return false, "no lib.require"
  end
  local ok, Surface = pcall(lib.require, "surface")
  if not ok or type(Surface) ~= "table" then return false, "no surface module" end
  if Surface._gen3IndoorWrapped then return true, "already" end
  local orig = Surface.isIndoorEncounterMap
  if type(orig) ~= "function" then return false, "no isIndoorEncounterMap" end

  Surface._gen3IndoorWrapped = true
  function Surface.isIndoorEncounterMap(game, map)
    local okO, hit = pcall(orig, game, map)
    if okO and hit == true then return true end
    local def = type(map) == "table" and map.def or nil
    if type(def) ~= "table" then return false end
    local t = tonumber(def.mapType)
    if t and GEN3_INDOOR_ENCOUNTER_TYPES[t] then return true end
    -- A Hoenn map that states it is not outdoor and still carries a land
    -- table is an interior encounter floor; the caller only reaches here
    -- when the map has an encounter table and no grass tiles at all.
    if def.outdoor == false then return true end
    return false
  end
  return true, "armed"
end

function Gen3Compat.noteWildsMod(mod)
  if type(mod) ~= "table" then return end
  Gen3Compat._wildsBindMod = mod
  do
    local okP, whyP = Gen3Compat.armModUiPush()
    local L = package.loaded["src.core.Logger"]
    if L and L.info and okP then
      pcall(L.info, "gen3 facade: ModUI.push routed to openModScreen (%s)",
        tostring(whyP))
    end
    local okS, whyS = Gen3Compat.armWildsSurface(mod.exports or mod)
    local Logger = package.loaded["src.core.Logger"]
    if Logger then
      if okS and Logger.info then
        pcall(Logger.info, "gen3 wilds host: cave surface armed (%s)", tostring(whyS))
      elseif not okS and Logger.warn then
        pcall(Logger.warn, "gen3 wilds host: cave surface NOT armed (%s)", tostring(whyS))
      end
    end
  end
  -- Wilds behavior/voxel repeatedly calls applyProviderSprite. SpeciesAssets
  -- has no Hoenn names, so water/Surskit guests flip colored → PLACEHOLDER.
  -- After each provider pass, re-assert the runtime follow sheet when the
  -- entity drifted to FALLBACK/? (engine-only wrap; mod untouched).
  local exports = mod.exports or mod
  local render = (exports and exports.render) or mod._owwildRender or mod.render
  if type(render) ~= "table" then
    local logic = (exports and exports.logic) or mod._owwildLogic or mod.logic
    render = logic and logic.render
  end
  if type(render) == "table" and type(render.applyProviderSprite) == "function"
      and not render._gen3KeepColoredWrapped then
    local origApply = render.applyProviderSprite
    function render.applyProviderSprite(self, entity, game, options)
      local ok, applied = pcall(origApply, self, entity, game, options)
      if not ok then return false end
      if type(entity) == "table" and type(game) == "table" then
        local sid = tostring(entity.spriteId or "")
        local path = nil
        if type(entity.sprite) == "table" and type(entity.sprite.def) == "table" then
          path = entity.sprite.def.image or entity.sprite.def.path
        end
        local drifted = entity.usingFallback == true
          or entity.blackFallbackSprite ~= nil
          or (type(sid) == "string" and (sid:upper():find("FALLBACK", 1, true)
                or sid:upper():find("PLACEHOLDER", 1, true)))
          or (type(path) == "string" and (path:upper():find("FALLBACK", 1, true)
                or path:upper():find("PLACEHOLDER", 1, true)
                or path:upper():find("POKEMON_MISSING", 1, true)
                or path:upper():find("SPAWN_PLACEHOLDER", 1, true)))
        if drifted then
          local stamped = Gen3Compat.refreshGuestSprite(game, entity)
          if stamped and not Gen3Compat._wildsRegressLogged then
            Gen3Compat._wildsRegressLogged = {}
          end
          if stamped and Gen3Compat._wildsRegressLogged then
            local sk = tostring(entity.species or "?")
            if not Gen3Compat._wildsRegressLogged[sk] then
              Gen3Compat._wildsRegressLogged[sk] = true
              local Logger = package.loaded["src.core.Logger"]
              if Logger and Logger.info then
                pcall(Logger.info,
                  "gen3 wilds host: restored colored sheet after provider regress species=%s",
                  sk)
              end
            end
          end
        end
      end
      return applied
    end
    render._gen3KeepColoredWrapped = true
  end
end

function Gen3Compat.tryBindPendingSprites(game)
  local mod = Gen3Compat._wildsBindMod
  if type(game) ~= "table" or type(mod) ~= "table" then return 0, "pending" end
  if game._wildsSpritesBound then
    -- Sheets already bound. Re-stamp only while some guests still show
    -- FALLBACK/? (parked before pokemon/sheets ready). Stop once clean so
    -- collectModOwGuests does not restamp every frame.
    if game._wildsGuestsFullyColored then return 0, "colored" end
    local colored, fallbackLeft, stamped = Gen3Compat.restampGuestSprites(game)
    if not game._wildsColorStampLogged then
      game._wildsColorStampLogged = true
      local Logger = package.loaded["src.core.Logger"]
      if Logger and Logger.info then
        pcall(Logger.info,
          "gen3 wilds host: guest sprites colored=%d fallback=%d stamped=%d",
          colored, fallbackLeft, stamped)
      end
    end
    if fallbackLeft == 0 and stamped >= 0 then
      game._wildsGuestsFullyColored = true
    end
    return stamped, "restamp"
  end
  local n, why = Gen3Compat.bindWildsRuntimeSprites(game, mod)
  if type(n) == "number" and n >= 0 and why ~= "no runtimeSheets" and why ~= "sheets not ready" then
    game._wildsSpritesBound = true
  end
  return n, why
end

function Gen3Compat.bindWildsRuntimeSprites(game, mod)
  if type(game) ~= "table" or type(mod) ~= "table" then
    return 0, "no game/mod"
  end
  local exports = mod.exports or mod
  local render = (exports and exports.render)
    or mod._owwildRender or mod.render
  if type(render) ~= "table" then
    local logic = (exports and exports.logic) or mod._owwildLogic or mod.logic
    render = logic and logic.render
  end
  local sheets = render and render.runtimeSheets
  if type(sheets) ~= "table" or type(sheets.spriteDef) ~= "function" then
    return 0, "no runtimeSheets"
  end
  if type(sheets.isReady) == "function" and not sheets:isReady() then
    if type(sheets.load) == "function" then pcall(function() sheets:load() end) end
  end
  if type(sheets.isReady) == "function" and not sheets:isReady() then
    return 0, "sheets not ready"
  end
  game.data = game.data or {}
  local sprites = game.data.sprites
  if type(sprites) ~= "table" then
    sprites = {}
    game.data.sprites = sprites
  end
  local bound = 0
  local function put(id, def)
    if type(id) ~= "string" or id == "" then return end
    if type(def) ~= "table" then return end
    local image = def.image or def.path
    if type(image) ~= "string" or image == "" then return end
    local existing = sprites[id]
    if type(existing) == "table" and (existing.image or existing.path)
        and existing.trueColor == true
        and not _wildsIsFallbackPath(existing.image or existing.path)
        and not _wildsIsFallbackId(id) then
      return
    end
    local frames = tonumber(def.frames) or tonumber(def.frameCount) or 6
    sprites[id] = {
      id = id,
      image = image,
      path = image,
      frames = frames,
      frameCount = frames,
      width = tonumber(def.width) or tonumber(def.frameWidth) or 16,
      height = tonumber(def.height) or tonumber(def.frameHeight) or 16,
      walker = true,
      trueColor = true,
    }
    bound = bound + 1
  end
  local function bindDex(dex, variant)
    dex = tonumber(dex)
    if not dex then return end
    local id = "SPRITE_OW_WILD_" .. tostring(dex)
    local ok, def = pcall(sheets.spriteDef, sheets, dex, variant or "normal", id)
    if ok and type(def) == "table" then put(id, def) end
    -- Also alias uppercase species-less dex form used by some lookups.
    if render and type(render.speciesSpriteIds) == "table" then
      if render.speciesSpriteIds[dex] == nil then
        render.speciesSpriteIds[dex] = id
      end
    end
  end
  local manifestSheets = sheets.manifest and sheets.manifest.sheets
  if type(manifestSheets) == "table" then
    for key, entry in pairs(manifestSheets) do
      local dex = nil
      if type(key) == "string" then
        dex = tonumber(key:match("^(%d+)"))
      elseif type(key) == "number" then
        dex = key
      end
      if not dex and type(entry) == "table" then
        dex = tonumber(entry.speciesId or entry.dex or entry.id)
      end
      if dex then bindDex(dex, "normal") end
    end
  else
    -- Fallback: probe a wide dex range when manifest shape is unexpected.
    local maxDex = tonumber(sheets.sheetCount) or 0
    if maxDex < 386 then maxDex = 386 end
    for dex = 1, maxDex do
      if sheets.hasSheet and sheets:hasSheet(dex, "normal") then
        bindDex(dex, "normal")
      end
    end
  end
  -- Shared fallback / placeholder from content registry into Data.
  for _, id in ipairs({ "SPRITE_OW_WILD_FALLBACK", "SPRITE_OW_WILD_PLACEHOLDER" }) do
    if type(sprites[id]) ~= "table" then
      local content = mod.content and mod.content.sprites
      local def = content and content.get and content:get(id)
      if type(def) == "table" then put(id, def) end
    end
  end

  -- Wilds spriteIdFor(species) keys speciesSpriteIds by SPECIES NAME
  -- ("ZIGZAGOON"), while content pokemon:each on Gen3 registered 0 rows
  -- (Registered sprites: 0). Dex-only data.sprites binds left that map empty
  -- → "no pre-registered overworld sprite; using fallback id". Alias each
  -- bound dex sheet under SPRITE_OW_WILD_<NAME> and fill speciesSpriteIds.
  if type(render.speciesSpriteIds) ~= "table" then
    render.speciesSpriteIds = {}
  end
  local idMap = render.speciesSpriteIds
  local function aliasSpecies(speciesKey, dex)
    if speciesKey == nil then return end
    local name = tostring(speciesKey)
    if name == "" then return end
    local sid = "SPRITE_OW_WILD_" .. name
    local dexId = "SPRITE_OW_WILD_" .. tostring(dex)
    local src = sprites[dexId] or sprites[sid]
    if type(src) ~= "table" then return end
    if type(sprites[sid]) ~= "table" then
      sprites[sid] = {
        id = sid,
        image = src.image or src.path,
        path = src.path or src.image,
        frames = src.frames or src.frameCount or 6,
        frameCount = src.frameCount or src.frames or 6,
        width = src.width or 16,
        height = src.height or 16,
        walker = true,
        trueColor = true,
      }
    end
    local function setAlias(key, val)
      if key == nil or val == nil then return end
      local cur = idMap[key]
      if cur == nil or _wildsIsFallbackId(tostring(cur)) then
        idMap[key] = val
      end
    end
    setAlias(speciesKey, sid)
    setAlias(name, sid)
    setAlias(name:upper(), sid)
    if dex ~= nil then
      setAlias(dex, sid)
      setAlias(tostring(dex), sid)
    end
  end
  local function sheetDexOf(row, fallbackId)
    if type(row) ~= "table" then
      return tonumber(fallbackId)
    end
    -- Followsheets are NATIONAL dex; Gen3 byIndex keys are internal ids.
    local dex = tonumber(row.nationalDex or row.dex or row.speciesId)
    if not dex and type(row.number) == "number" then dex = row.number end
    if not dex then dex = tonumber(fallbackId) end
    if not dex and type(game.nationalDexOf) == "function" and fallbackId ~= nil then
      local okN, n = pcall(game.nationalDexOf, game, fallbackId)
      if okN then dex = tonumber(n) end
    end
    return dex
  end
  local function ensureSheet(dex)
    if not dex then return false end
    if sprites["SPRITE_OW_WILD_" .. tostring(dex)] then return true end
    if type(sheets.hasSheet) == "function" and sheets:hasSheet(dex, "normal") then
      bindDex(dex, "normal")
    end
    return sprites["SPRITE_OW_WILD_" .. tostring(dex)] ~= nil
  end
  local function aliasRow(row, keyHint)
    if type(row) ~= "table" then return end
    local dex = sheetDexOf(row, keyHint)
    if not dex or not ensureSheet(dex) then return end
    if keyHint ~= nil then aliasSpecies(keyHint, dex) end
    if row.name then
      aliasSpecies(row.name, dex)
      local nk = tostring(row.name):upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
      if nk ~= "" then aliasSpecies(nk, dex) end
    end
    if row.id and type(row.id) == "string" then aliasSpecies(row.id, dex) end
  end
  local NEST_KEYS = { byIndex = true, byId = true, byName = true, maps = true, ids = true }
  local function walkPokemonTable(poke, depth)
    if type(poke) ~= "table" then return end
    depth = depth or 0
    if depth > 3 then return end
    -- Nested Gen3 indexes (pokemon.byIndex[288] = {name=ZIGZAGOON, nationalDex=263})
    for nest, _ in pairs(NEST_KEYS) do
      if nest ~= "ids" and type(poke[nest]) == "table" then
        walkPokemonTable(poke[nest], depth + 1)
      end
    end
    if type(poke.ids) == "table" then
      for _, id in ipairs(poke.ids) do
        local row = poke[id] or (poke.byId and poke.byId[id]) or (poke.maps and poke.maps[id])
        if type(row) ~= "table" and type(poke.byName) == "table" then
          row = poke.byName[id]
        end
        aliasRow(type(row) == "table" and row or {}, id)
      end
    end
    for k, row in pairs(poke) do
      if type(k) == "string" and NEST_KEYS[k] then
        -- already walked
      elseif type(k) == "string" and type(row) == "table" then
        aliasRow(row, k)
      elseif type(k) == "number" and type(row) == "table" then
        aliasRow(row, k)
      end
    end
  end
  local data = game.data
  walkPokemonTable(data and data.pokemon)
  walkPokemonTable(data and data.gen3Pokemon)
  -- Also alias every bound dex under SPRITE_OW_WILD_<dex> into idMap by dex.
  for id, def in pairs(sprites) do
    if type(id) == "string" then
      local dex = tonumber(id:match("^SPRITE_OW_WILD_(%d+)$"))
      if dex then
        idMap[dex] = idMap[dex] or id
        idMap[tostring(dex)] = idMap[tostring(dex)] or id
      end
    end
  end
  local named = 0
  for k, _ in pairs(idMap) do
    if type(k) == "string" and not tonumber(k) then named = named + 1 end
  end
  local Logger = package.loaded["src.core.Logger"]
  if Logger and Logger.info then
    pcall(Logger.info, "gen3 wilds host: speciesSpriteIds named=%d total=%d",
      named, (function()
        local n = 0
        for _ in pairs(idMap) do n = n + 1 end
        return n
      end)())
  end

  -- Rebind live Wilds Entity SpriteRenderers onto follower sheets now that
  -- speciesSpriteIds is name-keyed (spawn-time may have used FALLBACK_ID).
  do
    local logic = (exports and exports.logic) or mod._owwildLogic or mod.logic
    if type(render.refreshAllEntitySprites) == "function" and type(logic) == "table" then
      local okR, nR = pcall(render.refreshAllEntitySprites, render, logic, game)
      if okR and Logger and Logger.info then
        pcall(Logger.info, "gen3 wilds host: refreshed entity sprites %s", tostring(nR))
      end
    end
    -- Engine stamp: Hoenn names are absent from Wilds SpeciesAssets, so
    -- applyProviderSprite often no-ops; push runtime sheets onto guests.
    -- Log colored vs fallback once so boot shows whether FALLBACK/? cleared.
    local colored, fallbackLeft, stamped = Gen3Compat.restampGuestSprites(game)
    game._wildsColorStampLogged = true
    if Logger and Logger.info then
      pcall(Logger.info,
        "gen3 wilds host: stamped guest sprites colored=%d fallback=%d total=%d",
        colored, fallbackLeft, stamped)
    end
  end

  return bound, "bound"
end



-- ----------------------------------------------------------- Wilds Gen3 host
-- (engine-only; never edit AppData overworld_wild_spawns)
--
-- Official Wilds GameCompat only has Gen1/Gen2 adapters. With honest
-- GameVersion.generation()==3 those adapters stay off. This host lets Wilds
-- install Gen1 hooks against Gen3Compat's Gen1-shaped modOverworld WITHOUT
-- permanently remapping global GameVersion for ModTargets / the mod menu.
-- Guests park on game._modOwGuests only — never CAST_KEYS / trackInserts.

local wildsLoadGenDepth = 0
local wildsLoadGenOrig = nil
local wildsLoadGenTarget = nil

local function honestGenerationOf(GV, id)
  if not GV then return nil end
  if type(GV._gen3HonestGeneration) == "function" then
    local ok, g = pcall(GV._gen3HonestGeneration, id)
    if ok then return g end
  end
  if type(GV.generation) == "function" then
    local ok, g = pcall(GV.generation, id)
    if ok then return g end
  end
  return nil
end

--- Gen3 byMap row → Gen1-shaped encDef { grass, water, fishing }.
function Gen3Compat.bridgeEncountersForMap(game, mapId)
  if mapId == nil or not game then return nil end
  local pack = game.data and game.data.encounters
  local byMap = pack and pack.byMap
  if type(byMap) ~= "table" then return nil end
  local row = byMap[mapId] or byMap[tostring(mapId)]
  if type(row) ~= "table" and type(game.encountersFor) == "function" then
    local map = { id = mapId }
    if type(game.lookupMapById) == "function" then
      local ok, found = pcall(game.lookupMapById, game, mapId)
      if ok and found then map = found end
    end
    local ok, enc = pcall(game.encountersFor, game, map)
    if ok then row = enc end
  end
  if type(row) ~= "table" then return nil end

  local function speciesKey(species)
    if type(species) == "string" and species ~= "" then
      return species:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
    end
    local n = tonumber(species)
    if not n then return species end
    if type(game.speciesName) == "function" then
      local ok, name = pcall(game.speciesName, game, n)
      if ok and type(name) == "string" and name ~= ""
          and not name:match("^POKeMON") and not name:match("^[?%-]+$") then
        return name:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
      end
    end
    return n
  end

  local function kindFrom(info)
    if type(info) ~= "table" or type(info.slots) ~= "table" or #info.slots == 0 then
      return nil
    end
    local slots = {}
    for _, s in ipairs(info.slots) do
      if type(s) == "table" and s.species ~= nil then
        local lo = tonumber(s.minLevel) or tonumber(s.level) or 2
        local hi = tonumber(s.maxLevel) or lo
        if hi < lo then hi = lo end
        local level = lo
        if hi > lo then level = math.floor((lo + hi) / 2) end
        slots[#slots + 1] = {
          species = speciesKey(s.species),
          level = level,
        }
      end
    end
    if #slots == 0 then return nil end
    local rate = tonumber(info.rate) or 25
    if rate <= 0 then rate = 25 end
    return { rate = rate, slots = slots }
  end

  local enc = {
    grass = kindFrom(row.land),
    water = kindFrom(row.water),
    fishing = kindFrom(row.fish),
  }
  if not (enc.grass or enc.water or enc.fishing) then return nil end
  return enc
end

--- Brief load-only GameVersion.generation remap while Wilds' entry runs.
-- Restores honest generation before the loader continues. NOT a permanent lie.
function Gen3Compat.beginWildsLoadHost()
  local function isGV(t)
    return type(t) == "table" and type(t.generation) == "function"
  end
  local targets = {}
  local function add(t)
    if not isGV(t) then return end
    for i = 1, #targets do
      if targets[i] == t then return end
    end
    targets[#targets + 1] = t
  end
  add(package.loaded["src.core.GameVersion"])
  add(built["src.core.GameVersion"])
  if #targets == 0 then
    return function() end
  end
  wildsLoadGenDepth = wildsLoadGenDepth + 1
  if wildsLoadGenDepth > 1 then
    return function()
      wildsLoadGenDepth = math.max(0, wildsLoadGenDepth - 1)
    end
  end
  local patched = {}
  for i = 1, #targets do
    local GV = targets[i]
    local orig = GV.generation
    local origIsGen1, origIsGen2, origIsGen3 = GV.isGen1, GV.isGen2, GV.isGen3
    if type(GV._gen3HonestGeneration) ~= "function" then
      GV._gen3HonestGeneration = orig
    end
    -- Only generation() is remapped for Wilds GameCompat.detectGeneration.
    -- isGen1/isGen2/isGen3 stay honest so a mid-load ModTargets touch cannot
    -- see Ruby as Gen1 (the menu poison from the permanent 3→1 lie).
    function GV.generation(id)
      local g = orig(id)
      if g == 3 then return 1 end
      return g
    end
    if type(origIsGen1) == "function" then
      function GV.isGen1(id) return orig(id) == 1 end
    end
    if type(origIsGen2) == "function" then
      function GV.isGen2(id) return orig(id) == 2 end
    end
    if type(origIsGen3) == "function" then
      function GV.isGen3(id) return orig(id) == 3 end
    end
    patched[#patched + 1] = {
      GV = GV, orig = orig,
      origIsGen1 = origIsGen1, origIsGen2 = origIsGen2, origIsGen3 = origIsGen3,
    }
  end
  wildsLoadGenTarget = patched[1] and patched[1].GV
  wildsLoadGenOrig = patched[1] and patched[1].orig
  return function()
    wildsLoadGenDepth = math.max(0, wildsLoadGenDepth - 1)
    if wildsLoadGenDepth == 0 then
      for i = 1, #patched do
        local row = patched[i]
        row.GV.generation = row.orig
        if row.origIsGen1 then row.GV.isGen1 = row.origIsGen1 end
        if row.origIsGen2 then row.GV.isGen2 = row.origIsGen2 end
        if row.origIsGen3 then row.GV.isGen3 = row.origIsGen3 end
      end
      wildsLoadGenTarget = nil
      wildsLoadGenOrig = nil
    end
  end
end

--- Permanent wrap of Wilds' GameCompat (mod.exports.gameCompat) for Gen3.
-- Does not change GameVersion.generation(). Hosts Gen1 adapter + encounter bridge.

--- Gen3 has no Renderer Pipelines.present compositor, and Wilds only calls
-- behaviorTick:stepFromWorld from world.stepped when isGen2. Without a tick,
-- SpawnFx never reaches spawn_visible → _attach never parks guests → flat
-- drawModOwGuests and voxel posesOf both see nobody. Drive WILDS AI from
-- Game3's world.tick emit (engine-only; does not edit the Wilds mod).
--- Bridge Gen1-shaped Sound.playCry → Game3 Mp2k cry (internal species id).
-- SoftStub must not swallow this: playCry is assigned on the Sound table.
function Gen3Compat.playCryBridge(data, species)
  if Gen3Compat._gen3CryBusy then return nil end
  local game = live()
  if type(game) ~= "table" or type(game.playMonCry) ~= "function" then
    return nil
  end
  local sid = Gen3Compat.resolveBattleSpecies(game, species)
  if type(sid) ~= "number" then
    return nil
  end
  Gen3Compat._gen3CryBusy = true
  local ok = pcall(game.playMonCry, game, sid)
  Gen3Compat._gen3CryBusy = false
  if not ok then return nil end
  return game.monCrySrc
end

--- Ensure package.loaded Sound (or built adapter) has the Gen3 cry bridge,
-- even if an earlier softStub cached a no-op playCry.
function Gen3Compat.ensureSoundCryBridge()
  local Sound = package.loaded["src.core.Sound"]
  if type(Sound) ~= "table" then
    Sound = built["src.core.Sound"]
  end
  if type(Sound) ~= "table" then return false end
  -- Always rawset so a prior softStub no-op cannot stick.
  rawset(Sound, "playCry", function(data, species)
    return Gen3Compat.playCryBridge(data, species)
  end)
  Sound._gen3CryBridged = true
  Sound._gen3SoundHost = true
  return true
end

Gen3Compat.AREA_CRY_MIN_S = 8
Gen3Compat.AREA_CRY_MAX_S = 20

function Gen3Compat.areaCryBusy(game)
  if type(game) ~= "table" then return true end
  if game.phase ~= nil and game.phase ~= "play" then return true end
  if type(game.inBattlePhase) == "function" then
    local ok, busy = pcall(game.inBattlePhase, game)
    if ok and busy then return true end
  elseif game.phase == "battle" or game.phase == "battle_transition" then
    return true
  end
  -- START / talk / bag overlays: field is nil while free-walking.
  if type(game.field) == "table" and game.field.kind ~= nil then
    return true
  end
  if type(game.cryPlaying) == "function" then
    local ok, playing = pcall(game.cryPlaying, game)
    if ok and playing then return true end
  end
  return false
end

function Gen3Compat.collectAreaCryCandidates(game)
  local out = {}
  local seen = {}
  local function consider(e)
    if type(e) ~= "table" then return end
    if seen[e] then return end
    seen[e] = true
    -- Prefer live wild guests; skip markers without a species.
    local sp = e.species or e.wildSpecies
    if sp == nil or sp == "" then return end
    if e.hiddenMarker or e._spawnFxOnly then return end
    local sid = Gen3Compat.resolveBattleSpecies(game, sp)
    if type(sid) ~= "number" then return end
    out[#out + 1] = { entity = e, sid = sid, species = sp }
  end
  local guests = game and game._modOwGuests
  if type(guests) == "table" then
    for _, e in ipairs(guests) do consider(e) end
  end
  local mod = Gen3Compat._wildsBindMod
  if type(mod) == "table" then
    local exports = mod.exports or mod
    local logic = (exports and exports.logic) or mod._owwildLogic or mod.logic
    if type(logic) == "table" and type(logic.entities) == "table" then
      for _, e in pairs(logic.entities) do consider(e) end
    end
  end
  return out
end

function Gen3Compat.rollAreaCryCooldown()
  local lo = tonumber(Gen3Compat.AREA_CRY_MIN_S) or 8
  local hi = tonumber(Gen3Compat.AREA_CRY_MAX_S) or 20
  if hi < lo then hi = lo end
  return lo + math.random() * (hi - lo)
end

--- Periodic cries of live wild guests (engine side-channel; Wilds has none).
function Gen3Compat.tickAreaCries(game, dt)
  if type(game) ~= "table" then return false end
  dt = tonumber(dt) or 0
  Gen3Compat.ensureSoundCryBridge()
  if not Gen3Compat._areaCriesArmedLogged then
    Gen3Compat._areaCriesArmedLogged = true
    local Logger = package.loaded["src.core.Logger"]
    if Logger and Logger.info then
      pcall(Logger.info, "gen3 wilds host: area cries armed")
    end
  end
  if Gen3Compat.areaCryBusy(game) then return false end
  local cd = tonumber(game._gen3AreaCryCd)
  if cd == nil then
    game._gen3AreaCryCd = Gen3Compat.rollAreaCryCooldown()
    return false
  end
  cd = cd - dt
  if cd > 0 then
    game._gen3AreaCryCd = cd
    return false
  end
  game._gen3AreaCryCd = Gen3Compat.rollAreaCryCooldown()
  local cands = Gen3Compat.collectAreaCryCandidates(game)
  if #cands < 1 then return false end
  local pick = cands[math.random(1, #cands)]
  if type(game.playMonCry) ~= "function" then return false end
  local ok = pcall(game.playMonCry, game, pick.sid)
  return ok == true
end

function Gen3Compat.driveWildsAi(game, dt)
  local mod = Gen3Compat._wildsBindMod
  if type(mod) ~= "table" then return false end
  local exports = mod.exports or mod
  local tick = exports and exports.behaviorTick
  if type(tick) ~= "table" then return false end
  if type(tick.ensurePipeline) == "function" then
    pcall(tick.ensurePipeline, tick)
  end
  if type(tick.step) ~= "function" then return false end
  local ok = pcall(tick.step, tick, {
    dt = dt,
    game = game,
    source = "gen3_world_tick",
  })
  -- STEP THE FOLLOWER TOO.
  --
  -- ControlEngine picks ONE owner for trailer movement and the choice is
  -- Gen 1/2 shaped: OverworldController.update (Red/Blue), else Gold's
  -- World:step, else "pikachu_follower", which means it expects the engine
  -- to be driving src.world.PikachuFollower.update on its behalf.  Ruby
  -- drives none of the three -- Game3 runs its own field loop -- so on
  -- Hoenn the engine settled on the pikachu_follower fallback and was then
  -- never called at all: overworldUpdateCalls and wrappedUpdateCalls both
  -- stayed at 0 and the follower sat wherever it was first placed, which is
  -- the warp tile the player arrived on.
  --
  -- ControlEngine:update is the same entry the Gen 1 wrap calls after
  -- vanilla's own update, and it carries no owner check of its own, so
  -- calling it from the Gen 3 world tick puts Hoenn on equal footing
  -- without touching the mod or the owner it selected.
  pcall(Gen3Compat.driveWildsFollower, game, dt, exports)
  -- drop the previous map's parked trailers before they draw again
  do
    local ow
    if type(game.modOverworld) == "function" then
      local okOw, got = pcall(game.modOverworld, game)
      if okOw then ow = got end
    end
    pcall(Gen3Compat.pruneStaleGuests, game, ow)
  end
  -- Provider rebind during AI can flip Hoenn guests to ?; restamp lightly.
  if type(game) == "table" then
    pcall(Gen3Compat.restampGuestSprites, game)
    pcall(Gen3Compat.tickAreaCries, game, dt)
    pcall(Gen3Compat.ensureMapFishGroup, game)
  end
  return ok == true
end

-- THE PARTY EVERY GEN 1 MOD READS.
--
-- Red keeps the party at game.save.party, so the community's mods reach for
-- it directly rather than through any adapter: Wilds' partyTrailMons,
-- free_fly's flyer search and partyKnowsSurf, and others besides.  Game3
-- keeps the party at game.party and leaves game.save.party nil, so all of
-- them read an empty list and quietly concluded the player had no Pokemon --
-- no trailer to build, no eligible flyer, nothing to refuse out loud.
--
-- Mirrored BY REFERENCE so the two never drift within a frame, and refreshed
-- every tick because Game3 REPLACES game.party on load/continue rather than
-- mutating it in place; a one-time stamp would go stale at the title screen.
--
-- Safe to add: Game3:snapshotSave builds the persisted payload from explicit
-- fields (self.party, self.bag, ...) and never copies self.save wholesale, so
-- this is not written to disk.  It does reach mods through the save.writing
-- payload, where a real party is the honest answer anyway.
-- WHAT data.pokemon[species] ANSWERS ON HOENN.
--
-- Red stores its species records at data.pokemon[id], so the community's
-- mods index it directly -- free_fly's canLearnFly is
-- `game.data.pokemon[mon.species].tmhm`, and skylib's monName is the same
-- read.  Ruby keeps them one level down, at data.pokemon.byIndex[n], with a
-- name index beside it at data.pokemon.named.  A bare index therefore
-- answered nil on every Hoenn boot and the mod concluded the species did not
-- exist.
--
-- An __index metatable rather than a copy: byIndex holds 411 records and
-- duplicating them would double the memory and let the two drift after a mod
-- overrides one.  Only MISSING keys route, so data.pokemon.byIndex,
-- .names, .count and the rest still answer for themselves, and pairs() is
-- untouched -- nothing that walks the table sees a new entry.
--
-- Accepts a name as well as a number because Gen 1 ids ARE names
-- ("PIDGEOT"), which is what a ported mod will have in hand.
function Gen3Compat.armGen1DataViews(game)
  local data = type(game) == "table" and game.data or nil
  local pk = type(data) == "table" and data.pokemon or nil
  if type(pk) ~= "table" then return false, "no data.pokemon" end
  -- the metatable IS the marker; no sentinel key, so pairs() stays clean
  if getmetatable(pk) ~= nil then return true, "already" end
  local byIndex = rawget(pk, "byIndex")
  if type(byIndex) ~= "table" then return false, "nothing to route to" end
  -- NAME -> RECORD, built once and lazily.
  --
  -- Ruby publishes `names` as index -> NAME (the cart's own order, with slot
  -- 0 as "??????????") and `named` as a COUNT, not a map -- an easy pair to
  -- misread, and reading `named[key]` indexes a number.  Game3:resolveSpeciesId
  -- already does this properly, including the accented forms, so prefer it
  -- and keep the reverse map only as the fallback.
  -- Built from `names` alone, and DELIBERATELY not via Game3:resolveSpeciesId:
  -- that function probes `poke.byName`, a key Ruby does not have, which comes
  -- straight back through this __index as a "species name" and calls it again.
  -- The first version did exactly that and hung the boot.
  local nameToId = nil
  local function idForName(key)
    if nameToId == nil then
      nameToId = {}
      local names = rawget(pk, "names")
      if type(names) == "table" then
        for id, nm in pairs(names) do
          if type(nm) == "string" and nm ~= "" then
            nameToId[nm:upper()] = id
          end
        end
      end
      -- names is index -> NAME; a dataset that only carries records still
      -- resolves, from each row's own name
      if type(byIndex) == "table" then
        for id, row in pairs(byIndex) do
          local nm = type(row) == "table" and row.name or nil
          if type(nm) == "string" and nm ~= "" and nameToId[nm:upper()] == nil then
            nameToId[nm:upper()] = tonumber(row.id) or id
          end
        end
      end
    end
    return nameToId[tostring(key):upper()]
  end
  -- A SPECIES RECORD'S tmhm, IN THE SHAPE A GEN 1 MOD CAN READ.
  --
  -- Red lists a species' machine moves by NAME, and mods loop it looking for
  -- one: free_fly's canLearnFly is `for _, m in ipairs(def.tmhm) do if m ==
  -- "FLY"`, and hm_anywhere_gen2's canLearnHM does the same over
  -- entry.tmhm / entry.tms.  Ruby stores two packed 32-bit words -- Sceptile
  -- is {3464316723, ...} -- so the loop ran twice over two integers, matched
  -- nothing, and every mon "could not learn" every HM.
  --
  -- Handed back through a VIEW rather than written onto the record, because
  -- Game3:canLearnTMHM reads that same field as a bitfield and replacing it
  -- would break the cart's own TM screen.  The engine reads species through
  -- Game3:speciesRow, which indexes byIndex directly and never passes through
  -- this metatable, so the raw row and the view coexist.
  local Game3 = require("src.core.Game3")
  local views = setmetatable({}, { __mode = "k" })

  local function tmhmNames(raw)
    local bits = raw and raw.tmhm
    if type(bits) ~= "table" then return nil end
    local list = game.data and game.data.moves and game.data.moves.tmhmMoves
    if type(list) ~= "table" then list = Game3.TMHM_MOVES end
    if type(list) ~= "table" then return nil end
    local out = {}
    -- 58 machines: TM01..TM50 then HM01..HM08, bit n <-> list[n + 1], the
    -- same indexing Game3.tmhmIndex uses
    for tm = 0, 57 do
      local word = (tm < 32) and (bits[1] or 0) or (bits[2] or 0)
      local bit = (tm < 32) and tm or (tm - 32)
      if math.floor(word / (2 ^ bit)) % 2 == 1 then
        local moveId = list[tm + 1]
        local name = nil
        if moveId and type(game.moveName) == "function" then
          local okN, nm = pcall(game.moveName, game, moveId)
          if okN then name = nm end
        end
        if type(name) == "string" and name ~= "" then
          out[#out + 1] = name:upper():gsub("%s+", "_")
        end
      end
    end
    return out
  end

  local function viewFor(raw)
    if type(raw) ~= "table" then return raw end
    local hit = views[raw]
    if hit then return hit end
    local names = nil
    local view = setmetatable({}, { __index = function(_, k)
      if k == "tmhm" or k == "tms" then
        if names == nil then names = tmhmNames(raw) or false end
        if names ~= false then return names end
        return raw.tmhm
      end
      return raw[k]
    end })
    views[raw] = view
    return view
  end

  setmetatable(pk, { __index = function(_, key)
    if type(key) == "number" then
      return type(byIndex) == "table" and viewFor(byIndex[key]) or nil
    end
    -- Gen 1 ids ARE names ("PIDGEOT"), which is what a ported mod holds
    if type(key) ~= "string" then return nil end
    local id = idForName(key)
    if id == nil then return nil end
    return viewFor(byIndex[id])
  end })

  -- hm_anywhere_gen2 looks the species up in data.pokedex, which Ruby has no
  -- table for at all.  Same records, same bridge.
  if rawget(data, "pokedex") == nil then data.pokedex = pk end
  return true, "armed"
end

-- THE BAG AND THE BADGES, IN GEN 1'S SHAPE.
--
-- Red keeps both in one flat map at `game.save.inventory`, keyed by name and
-- holding a count, and every ported mod reads it straight:
-- hm_anywhere_gen2's ownedHM walks it for "HM01", its hasBadge falls back to
-- `inventory[badge]`, and free_fly's badgeOk is literally
-- `game.save.inventory.THUNDERBADGE`.  Ruby keeps items in `game.bag` as
-- {id=n, count=n} slots and badges as engine flags, so that map was nil and
-- every one of those checks answered "you don't have it".
--
-- Badges are mapped BY WHAT THEY AUTHORISE rather than by name, because the
-- names do not correspond across regions: Hoenn's Feather Badge is the one
-- that permits FLY, so it is what a mod asking for Kanto's THUNDERBADGE or
-- Johto's STORMBADGE actually wants to know about.  ZEPHYRBADGE guards FLASH
-- and ROCK SMASH in Johto and Hoenn splits those across two badges; it takes
-- the stricter of the two so the bridge never unlocks more than the cart
-- would.  WHIRLPOOL has no Hoenn equivalent and is deliberately left unset.
local GEN1_BADGE_FOR_HOENN = {
  -- Kanto
  CASCADEBADGE = 1,  -- CUT      <- Stone
  BOULDERBADGE = 2,  -- FLASH    <- Knuckle
  RAINBOWBADGE = 4,  -- STRENGTH <- Heat
  SOULBADGE    = 5,  -- SURF     <- Balance
  THUNDERBADGE = 6,  -- FLY      <- Feather
  -- Johto
  HIVEBADGE    = 1,  -- CUT      <- Stone
  ZEPHYRBADGE  = 3,  -- FLASH + ROCK SMASH; Dynamo is the stricter of the two
  PLAINBADGE   = 4,  -- STRENGTH <- Heat
  FOGBADGE     = 5,  -- SURF     <- Balance
  STORMBADGE   = 6,  -- FLY      <- Feather
  RISINGBADGE  = 8,  -- WATERFALL<- Rain
}

local function bagSignature(game)
  local bag = rawget(game, "bag")
  if type(bag) ~= "table" then return "nobag" end
  local n = #bag
  local sum = 0
  for i = 1, n do
    local slot = bag[i]
    if type(slot) == "table" then
      sum = sum + (tonumber(slot.id) or 0) * 977 + (tonumber(slot.count) or 0)
    end
  end
  local badges = 0
  if type(game.hasBadge) == "function" then
    for b = 1, 8 do
      local ok, has = pcall(game.hasBadge, game, b)
      if ok and has then badges = badges + 2 ^ (b - 1) end
    end
  end
  return n .. ":" .. sum .. ":" .. badges
end

function Gen3Compat.syncSaveInventory(game)
  if type(game) ~= "table" then return false end
  local save = rawget(game, "save")
  if type(save) ~= "table" then return false end
  -- rebuilt only when the bag or the badge set actually moved; this runs on
  -- the world tick and a fresh table every frame would be pure garbage
  local sig = bagSignature(game)
  if save._gen3InventorySig == sig and type(save.inventory) == "table" then
    return true
  end
  local items = game.data and game.data.items
  local byId = type(items) == "table" and items.byId or nil
  local inv = {}
  local bag = rawget(game, "bag")
  if type(bag) == "table" then
    for i = 1, #bag do
      local slot = bag[i]
      local id = type(slot) == "table" and tonumber(slot.id) or nil
      local count = type(slot) == "table" and tonumber(slot.count) or nil
      if id and count and count > 0 then
        -- keyed by number AND by Gen 1 name: a mod may hold either
        inv[id] = (inv[id] or 0) + count
        local rec = byId and byId[id]
        local name = type(rec) == "table" and rec.name or nil
        if type(name) == "string" and name ~= "" then
          local key = name:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]", "")
          if key ~= "" then inv[key] = (inv[key] or 0) + count end
        end
      end
    end
  end
  if type(game.hasBadge) == "function" then
    for badgeName, hoennBadge in pairs(GEN1_BADGE_FOR_HOENN) do
      local ok, has = pcall(game.hasBadge, game, hoennBadge)
      if ok and has then inv[badgeName] = 1 end
    end
  end
  save.inventory = inv
  save._gen3InventorySig = sig
  return true
end

-- WHY FREEFLY NEVER APPEARED, EVEN WITH THE BADGE AND A FLY USER.
--
-- free_fly asks `eligibleFlyer` three questions in order:
--
--   1. is this the gift bird?                     -- no
--   2. does the mon KNOW Fly?                     -- Sky.knowsMove(mon, "FLY")
--   3. could it LEARN Fly, and is the engine's
--      eligibility chain answerable?              -- canLearnFly + wantsHook
--
-- Question 2 is `mv.id == "FLY"`.  Gen 1 names its moves; Ruby numbers them,
-- so a Rayquaza with Fly in slot 1 answers NO.  Every Hoenn boot therefore
-- falls through to question 3, whose second half is
-- `Runtime.wantsHook("fieldmove.eligibility")` -- true only when some OTHER
-- mod happens to have wrapped that hook.  With one loaded (qol_toggles'
-- FIELD MOVES ALL) takeoff worked; without one it was impossible, and the
-- difference is invisible from inside free_fly.
--
-- Ruby emits and honours that hook itself -- Game3:partyKnowsMove routes
-- every field-move question through it -- so an empty chain meant "no mod
-- registered", never "Ruby cannot answer".  Registering the engine's own
-- pass-through makes wantsHook say what is actually true.  Priority is far
-- below any mod's default of 0, and the link returns next(...) untouched, so
-- it changes no answer; it only stops the chain being empty.
function Gen3Compat.armFieldMoveChain(game)
  local loader = type(game) == "table" and game.mods or nil
  local hooks = type(loader) == "table" and loader.hooks or nil
  if type(hooks) ~= "table" or type(hooks.wrap) ~= "function" then
    return false, "no hooks"
  end
  if hooks._gen3FieldMoveChain then return true, "already" end
  hooks._gen3FieldMoveChain = true
  local ok = pcall(hooks.wrap, hooks, "fieldmove.eligibility",
    function(next, ...) return next(...) end,
    -10000, "gen3-compat")
  if not ok then
    hooks._gen3FieldMoveChain = nil
    return false, "wrap failed"
  end
  return true, "armed"
end

-- DRIVE THE SKY MODS' PER-FRAME TICK.
--
-- free_fly and wild_skies share one "self-healing wrap" over Gen 1's
-- OverworldController.update: Sky.ensureUpdateWrap registers each mod's tick
-- under a key (free_fly uses "__freeFlyTick") in OC.__skyTickKeys, and the
-- wrapped update calls every registered tick once per frame as
-- `tick(state, dt)`.
--
-- Ruby has no OverworldController.update to wrap -- Game3 runs its own field
-- loop -- so the ticks were registered and never called.  free_fly therefore
-- took off (state flipped, "press B to land" printed) and then hung at
-- altitude 0 forever, because the climb happens in that tick.
--
-- Driven through the family's OWN registry rather than by naming
-- __freeFlyTick here, so wild_skies and any later sibling are driven by the
-- same code without the engine knowing their key.
-- THE FLIGHT LIFT, WHEN THE MOD DID NOT PUBLISH freeFlyAlt.
--
-- Game3:drawPlayer already raises the player by `player.freeFlyAlt`, which
-- is how free_fly lifts on Gen 1.  But the mod writes that field only on its
-- VOXEL branch; the plain 2D branch sets it too, and on Ruby neither is
-- reached -- freeFlying was true while freeFlyAlt stayed nil, so the lift
-- was skipped and flight read as walking through walls at ground level.
--
-- exports.altitude() is the mod's own public answer for the same number
-- (`flying() and state.alt or 0`), so ask it rather than reaching into the
-- mod's branch logic.
-- THE MOD'S HIGH-RESOLUTION OVERWORLD ART.
--
-- Wilds draws from generated/followsprites_runtime, a 16x96 downscale: Kanto
-- species survive it, Hoenn ones become unidentifiable blobs.  The mod also
-- ships enhanced_overworld art at four times the size with real directional
-- walk cycles -- measured for Zigzagoon: a 128x128 atlas of 32x32 cells,
-- rows down / left / right / up, four frames each.
--
-- CELL SIZE VARIES PER SPECIES.  Zigzagoon is 32x32; Groudon is 64x64 in a
-- 256x256 atlas.  An earlier attempt drew these quads against the 16px
-- runtime coordinates and produced followers at mismatched sizes -- so the
-- geometry is read from the quad itself, never assumed.
--
-- Returns image, quad, width, height, or nil when anything is missing, so
-- the caller keeps its existing art rather than losing the sprite.
local GEN3_DIR_FOR_FACING = {
  north = "up", up = "up", back = "up",
  south = "down", down = "down", front = "down",
  west = "left", left = "left",
  east = "right", right = "right",
}

function Gen3Compat.wildsEnhancedArt(game, entity)
  if type(game) ~= "table" or type(entity) ~= "table" then return nil end
  local mod = Gen3Compat._wildsBindMod
  local exports = mod and (mod.exports or mod) or nil
  local an = exports and exports.animated or nil
  if type(an) ~= "table" or type(an.getImage) ~= "function"
      or type(an.getQuad) ~= "function" then
    return nil
  end
  if type(an.isReady) == "function" then
    local okR, ready = pcall(an.isReady, an)
    if not okR or not ready then return nil end
  end
  local dex = Gen3Compat.nationalDexOfSpecies(game, entity.species)
  if not dex then
    local fs = rawget(entity, "_wildsFollowerSpecies")
    if fs ~= nil then dex = Gen3Compat.nationalDexOfSpecies(game, fs) end
    if not dex and type(fs) == "number" then dex = fs end
  end
  if not dex then return nil end
  local dir = GEN3_DIR_FOR_FACING[tostring(entity.facing or "down"):lower()] or "down"
  -- four frames per direction; step them off the entity's own clock so a
  -- standing mon rests on frame 1 and a moving one walks
  local frame = 1
  if entity.moving then
    frame = math.floor((tonumber(entity.animClock) or 0) / 8) % 4 + 1
  end
  local okI, img = pcall(an.getImage, an, dex, nil)
  if not okI or not img then return nil end
  local okQ, quad = pcall(an.getQuad, an, dex, "walk", dir, frame, nil)
  if not okQ or not quad or type(quad.getViewport) ~= "function" then return nil end
  local okV, _, _, qw, qh = pcall(quad.getViewport, quad)
  if not okV or not qw or not qh or qw <= 0 or qh <= 0 then return nil end
  return img, quad, qw, qh
end

-- POINT A GUEST'S SPRITE RECORD AT THE MOD'S BETTER ART.
--
-- Wilds draws from generated/followsprites_runtime, a 16px downscale that
-- turns Hoenn species into unrecognisable blobs.  It also ships
-- enhanced_overworld/followsprites at 32px (some species 64px) with real
-- directional frames.
--
-- This changes DATA, not the draw: the record keeps its existing shape and
-- only its path and cell size move, so the ordinary blit renders it.  The
-- file is checked before anything is written, and on any doubt the record is
-- left exactly as it was -- an earlier attempt drew the better art directly
-- and, when it resolved to nothing on a device, painted an empty sprite
-- while suppressing the fallback, so the map came up bare.
function Gen3Compat.upgradeGuestArt(game, entity)
  if type(game) ~= "table" or type(entity) ~= "table" then return false end
  local sprites = game.data and game.data.sprites
  local sid = entity.spriteId
  local rec = type(sprites) == "table" and sid and sprites[sid] or nil
  if type(rec) ~= "table" then return false end
  if rec._gen3ArtUpgraded then return true end

  local dex = Gen3Compat.nationalDexOfSpecies(game, entity.species)
  if not dex then
    local fs = rawget(entity, "_wildsFollowerSpecies")
    if fs ~= nil then dex = Gen3Compat.nationalDexOfSpecies(game, fs) end
    if not dex and type(fs) == "number" then dex = fs end
  end
  if type(dex) ~= "number" then return false end

  local path = ("mods/overworld_wild_spawns/assets/enhanced_overworld/"
    .. "followsprites/%03d-b-n.png"):format(dex)
  if not (love and love.filesystem and love.filesystem.getInfo) then return false end
  if not love.filesystem.getInfo(path) then
    -- Do NOT give up permanently on the first miss: the mod's assets are not
    -- always reachable on the earliest ticks, and latching the flag there
    -- meant the upgrade never ran again for the rest of the session.  A few
    -- retries, then stop, so a species with genuinely no art costs nothing.
    local tries = (rec._gen3ArtTries or 0) + 1
    rec._gen3ArtTries = tries
    if tries >= 10 then rec._gen3ArtUpgraded = true end
    return false
  end
  -- the sheet must actually load, and its cell size is read from it rather
  -- than assumed: 32px for most, 64px for the larger species
  local okI, img = pcall(love.graphics.newImage, path)
  if not okI or not img then
    rec._gen3ArtUpgraded = true
    return false
  end
  local iw, ih = img:getDimensions()
  if iw < 32 or ih < 32 then
    rec._gen3ArtUpgraded = true
    return false
  end
  local cell = math.floor(iw / 4)      -- four columns of frames
  if cell < 16 then cell = 16 end
  rec.path, rec.image = path, path
  rec.width, rec.height = cell, cell
  rec.frameCount = math.max(1, math.floor(ih / cell))
  rec.frames = rec.frameCount
  rec._gen3ArtUpgraded = true
  return true
end

function Gen3Compat.freeFlyLift(game)
  if type(game) ~= "table" then return 0 end
  local loader = game.mods
  local exports = type(loader) == "table" and loader.exports or nil
  local ff = type(exports) == "table" and exports.free_fly or nil
  if type(ff) ~= "table" or type(ff.altitude) ~= "function" then return 0 end
  local ok, alt = pcall(ff.altitude)
  if not ok then return 0 end
  alt = tonumber(alt) or 0
  if alt < 0 then return 0 end
  return alt
end

function Gen3Compat.driveSkyTicks(game, dt)
  if type(game) ~= "table" then return 0 end
  local OC = Gen3Compat.resolve and Gen3Compat.resolve("src.world.OverworldController")
  if type(OC) ~= "table" then return 0 end
  local keys = rawget(OC, "__skyTickKeys")
  if type(keys) ~= "table" or #keys == 0 then return 0 end
  local ow
  if type(game.modOverworld) == "function" then
    local okOw, got = pcall(game.modOverworld, game)
    if okOw then ow = got end
  end
  if type(ow) ~= "table" then return 0 end
  local step = tonumber(dt)
  if not step or step <= 0 then step = 1 / 60 end
  -- Reentrancy is guarded with a PRIVATE flag, not OC.__skyTicking.
  --
  -- The family's dispatcher sets __skyTicking only around the original
  -- update and clears it BEFORE running the ticks, so a tick never observes
  -- it set.  Holding it across the tick loop is a state the mods never see
  -- on Gen 1, and free_fly's tick reads it -- which is why the climb ran
  -- when called directly and did nothing from the world tick.
  if Gen3Compat._skyTickBusy then return 0 end
  Gen3Compat._skyTickBusy = true
  local ran = 0
  for i = 1, #keys do
    local tick = OC[keys[i]]
    if type(tick) == "function" then
      local ok, err = pcall(tick, ow, step)
      if ok then
        ran = ran + 1
      elseif not Gen3Compat._skyTickFailed then
        Gen3Compat._skyTickFailed = {}
        local Logger = package.loaded["src.core.Logger"]
        if Logger and Logger.warn then
          pcall(Logger.warn, "gen3 sky tick %s failed: %s",
            tostring(keys[i]), tostring(err))
        end
      end
    end
  end
  Gen3Compat._skyTickBusy = nil
  return ran
end

function Gen3Compat.syncSaveParty(game)
  if type(game) ~= "table" then return false end
  local save = rawget(game, "save")
  local party = rawget(game, "party")
  if type(save) ~= "table" or type(party) ~= "table" then return false end
  if save.party ~= party then save.party = party end
  Gen3Compat.stampModNicknames(game, party)
  return true
end

-- WHY A FOLLOWER SAID "288 is now following you!".
--
-- Gen 1 mons carry a NAME as their species and a `nickname` field beside it,
-- so ported mods print `mon.nickname or mon.species` and get a word either
-- way.  Ruby numbers its species and keeps a player-set nickname in
-- `mon.name`, so that chain fell through to the raw number.
--
-- Stamped rather than translated at the message, because the mod does the
-- formatting itself: by the time text reaches the engine it is already
-- "288 is now following you!" and picking the number back out of a sentence
-- would be guesswork.
--
-- `nickname` is safe to add: Game3 reads `mon.name` for a nickname and
-- snapshotMon persists only `species` and `name`, so this never reaches the
-- save file.  Refreshed rather than stamped once, so renaming a mon in the
-- party screen updates what a mod calls it.
function Gen3Compat.stampModNicknames(game, party)
  if type(game) ~= "table" or type(party) ~= "table" then return 0 end
  if type(game.speciesName) ~= "function" then return 0 end
  local n = 0
  for i = 1, #party do
    local mon = party[i]
    if type(mon) == "table" and type(mon.species) == "number" then
      -- a real nickname the player set wins, exactly as it does on Gen 1
      local want = mon.name
      if type(want) ~= "string" or want == "" then
        local ok, nm = pcall(game.speciesName, game, mon.species)
        if ok and type(nm) == "string" and nm ~= "" then want = nm end
      end
      if type(want) == "string" and want ~= "" and mon.nickname ~= want then
        mon.nickname = want
        n = n + 1
      end
    end
  end
  return n
end

-- True when the follower engine has work the player actually asked for:
-- a chosen follower, or trailers still standing that need clearing.
function Gen3Compat.wildsFollowerWanted(game, exports, ow)
  -- THE COUNT IS AUTHORITATIVE, AND IT IS CHECKED FIRST.
  --
  -- Two earlier versions of this gate both failed on hardware:
  --
  --   1. asking getActiveFollowerMon -- which is not a record of a choice.
  --      With nothing selected it falls back to the topmost healthy party
  --      mon, so it answers non-nil on virtually any save;
  --   2. asking selectedMonKey first -- which the mod REPOPULATES by itself.
  --      Selection:reconcile re-picks a follower after a map change, so a
  --      player who had chosen nobody got a key anyway and the gate passed.
  --
  -- The follower count is the setting the player actually controls, so it
  -- decides.  Zero means zero, whatever the mod has re-selected behind it.
  local trailersStanding = false
  local ents = type(ow) == "table" and ow.entities or nil
  if type(ents) == "table" then
    for _, e in pairs(ents) do
      if type(e) == "table" and rawget(e, "_wildsFollowerSpecies") ~= nil then
        trailersStanding = true
        break
      end
    end
  end

  if type(exports) == "table" and type(exports.followerCount) == "function" then
    local okC, n = pcall(exports.followerCount, game)
    if okC and tonumber(n) ~= nil and tonumber(n) <= 0 then
      -- keep running only long enough to take down anything still standing
      return trailersStanding
    end
  end

  -- a count above zero still needs the player to have chosen someone
  local follower = type(exports) == "table" and exports.follower or nil
  local selection = type(follower) == "table" and follower.selection or nil
  local state = type(selection) == "table" and selection.state or nil
  if type(state) == "table" then
    if state.selectedMonKey ~= nil then return true end
    return trailersStanding
  end
  if type(exports) == "table"
      and type(exports.getActiveFollowerMon) == "function" then
    local ok, mon = pcall(exports.getActiveFollowerMon, game)
    if ok and mon ~= nil then return true end
  end
  return trailersStanding
end

function Gen3Compat.driveWildsFollower(game, dt, exports)
  if type(game) ~= "table" then return false end
  local follower = exports and exports.follower
  local ce = type(follower) == "table" and follower.control or nil
  if type(ce) ~= "table" or type(ce.update) ~= "function" then return false end
  -- Only the fallback owner is ours to drive.  If a Gen 1/2 wrap ever does
  -- own the trailer on this boot, stepping it here as well would move every
  -- trailer twice in a frame.
  local owner = ce._trailerUpdateOwner
  if owner ~= nil and owner ~= "pikachu_follower" then return false end
  Gen3Compat.syncSaveParty(game)
  local ow
  if type(game.modOverworld) == "function" then
    local okOw, got = pcall(game.modOverworld, game)
    if okOw then ow = got end
  end
  if type(ow) ~= "table" then return false end
  -- NOTHING FOLLOWS THE PLAYER UNTIL THEY SAY SO.
  --
  -- ControlEngine:followerCount defaults to 1 and syncTrailers in follow/pack
  -- mode then trails the party, so simply driving the engine put a pack on
  -- the map at boot -- five Pokemon nobody asked for.  On Kanto that is the
  -- mod's intended default and the player opted in by installing it; on Ruby
  -- the whole path was dead until this driver existed, so switching it on
  -- silently changed the game under a save that never consented.
  --
  -- An explicit selection is the gate.  Trailers already on the map keep the
  -- engine running so it can take them off again -- stopping the moment the
  -- selection clears would strand whatever was mid-step.
  if not Gen3Compat.wildsFollowerWanted(game, exports, ow) then return false end
  local step = tonumber(dt)
  if not step or step <= 0 then step = 1 / 60 end
  local okU = pcall(ce.update, ce, game, ow, {
    dt = step,
    source = "gen3_world_tick",
  })
  return okU == true
end

function Gen3Compat.armWildsHost(GC)
  if type(GC) ~= "table" then return false, "no GameCompat" end
  if GC._gen3WildsHostArmed then return true, "already" end

  local function engineGen(game)
    local GV = package.loaded["src.core.GameVersion"]
    local g = honestGenerationOf(GV)
    if type(g) == "number" then return g end
    if type(game) == "table" and tonumber(game.generation) then
      return tonumber(game.generation)
    end
    return nil
  end

  local origGeneration = GC.generation
  local origCurrent = GC.current
  local origEncounters = GC.encountersForMap
  local Gen1 = GC.Gen1

  function GC.generation(mod, game)
    local g
    if type(origGeneration) == "function" then
      local ok, got = pcall(origGeneration, mod, game)
      if ok then g = got end
    end
    if g == nil then g = engineGen(game) end
    -- Host Gen1 adapter against Gen3 overworld; GameVersion stays gen3.
    if g == 3 then return 1 end
    return g
  end

  function GC.current(mod, game)
    local g = GC.generation(mod, game)
    if g == 1 and Gen1 and Gen1.supported then return Gen1 end
    if type(origCurrent) == "function" then
      return origCurrent(mod, game)
    end
    return nil
  end

  -- THE PARTY LIVES SOMEWHERE ELSE ON RUBY.
  --
  -- GameCompat.party defers to the active adapter, which this facade pins to
  -- Gen1, and Gen1's reads game.save.party.  Game3 keeps the party at
  -- game.party and leaves game.save.party nil, so the call answered nil on
  -- every Hoenn boot.  Everything the follower does starts there:
  -- Selection:selectFollower bails at `getParty(game)`, getActiveFollowerMon
  -- returns nil, and no trailer is ever built -- which is why the follower
  -- never moved regardless of who was stepping it.
  --
  -- Falls back only when the adapter has nothing, so a Gen 1/2 boot keeps
  -- reading its own save exactly as before.
  local function gen3Party(game)
    if type(game) ~= "table" then return nil end
    local p = rawget(game, "party")
    if type(p) == "table" and #p > 0 then return p end
    return nil
  end

  local origParty = GC.party
  function GC.party(game)
    if type(origParty) == "function" then
      local ok, hit = pcall(origParty, game)
      if ok and type(hit) == "table" and #hit > 0 then return hit end
    end
    return gen3Party(game)
  end

  if Gen1 and type(Gen1.party) == "function" then
    local origGen1Party = Gen1.party
    function Gen1.party(game)
      local ok, hit = pcall(origGen1Party, game)
      if ok and type(hit) == "table" and #hit > 0 then return hit end
      return gen3Party(game)
    end
  end

  function GC.encountersForMap(game, mapId, ctx)
    if type(origEncounters) == "function" then
      local ok, hit = pcall(origEncounters, game, mapId, ctx)
      if ok and hit ~= nil then return hit end
    end
    return Gen3Compat.bridgeEncountersForMap(game, mapId)
  end

  if Gen1 and type(Gen1.encountersForMap) == "function" then
    local origGen1Enc = Gen1.encountersForMap
    function Gen1.encountersForMap(game, mapId, ctx)
      local ok, hit = pcall(origGen1Enc, game, mapId, ctx)
      if ok and hit ~= nil then return hit end
      return Gen3Compat.bridgeEncountersForMap(game, mapId)
    end
  end

  -- Park Wilds Entity attaches on _modOwGuests (side channel). Wilds still
  -- writes ow.entities itself; we do NOT CAST_KEYS / trackInserts — Game3
  -- draw + ephemeral pipeline state merge read this list instead.
  if type(GC.attachWildEntity) == "function" and not GC._gen3AttachParked then
    local origAttach = GC.attachWildEntity
    function GC.attachWildEntity(ow, entity, game)
      local result = origAttach(ow, entity, game)
      local g = game
      if type(g) ~= "table" and type(resolveGame) == "function" then
        g = resolveGame()
      end
      if type(g) ~= "table" and type(ow) == "table" then
        -- modOverworld proxy may carry .game
        g = ow.game or (ow._game) or g
      end
      if type(g) == "table" and type(entity) == "table" then
        Gen3Compat.parkModOwGuest(g, entity)
      end
      return result
    end
    GC._gen3AttachParked = true
  end
  if type(GC.detachWildEntity) == "function" and not GC._gen3DetachParked then
    local origDetach = GC.detachWildEntity
    function GC.detachWildEntity(ow, entity, game)
      local result = origDetach(ow, entity, game)
      local g = game
      if type(g) ~= "table" and type(resolveGame) == "function" then
        g = resolveGame()
      end
      if type(g) == "table" and type(entity) == "table" then
        Gen3Compat.unparkModOwGuest(g, entity)
      end
      return result
    end
    GC._gen3DetachParked = true
  end

  -- Contact battle: Wilds Gen1 adapter calls world:queueScript(start_battle),
  -- but Gen3 WorldAPI has no queueScript. Route to Game3:startWildBattle.
  local function startGen3Wild(world, species, level, game)
    local g = game
    if type(g) ~= "table" and type(world) == "table" then
      g = world.game or world._game
    end
    if type(g) ~= "table" and type(resolveGame) == "function" then
      g = resolveGame()
    end
    if type(g) ~= "table" or type(g.startWildBattle) ~= "function" then
      return nil, "no Game3.startWildBattle"
    end
    -- FREEFLY: never start Wilds/contact battles while airborne.
    if type(g.isFreeFlying) == "function" then
      local okF, flying = pcall(g.isFreeFlying, g)
      if okF and flying then
        return nil, "free flying"
      end
    elseif g._modPlayerStore and (g._modPlayerStore.freeFlying
        or (g._modPlayerStore.freeFlyAlt or 0) > 0) then
      return nil, "free flying"
    end
    local sid = Gen3Compat.resolveBattleSpecies(g, species)
    if type(sid) ~= "number" then
      local Logger = package.loaded["src.core.Logger"]
      if Logger and Logger.warn then
        pcall(Logger.warn,
          "gen3 wilds host: battle species unresolved %s → %s",
          tostring(species), tostring(sid))
      end
      return nil, "unresolved battle species " .. tostring(species)
    end
    local ok, ret = pcall(g.startWildBattle, g, sid, tonumber(level) or 5)
    if not ok then return nil, tostring(ret) end
    if ret == false then return nil, "startWildBattle returned false" end
    return true
  end

  if Gen1 and type(Gen1.startWildBattle) == "function" and not Gen1._gen3WildBattleWrapped then
    local origGen1Wild = Gen1.startWildBattle
    function Gen1.startWildBattle(world, species, level)
      local ok, err = startGen3Wild(world, species, level, nil)
      if ok then return true end
      -- Fall through only if the world actually has Gen1 queueScript.
      if world and type(world.queueScript) == "function" then
        return origGen1Wild(world, species, level)
      end
      return nil, err or "no Gen3 wild battle"
    end
    Gen1._gen3WildBattleWrapped = true
  end

  if type(GC.startWildBattle) == "function" and not GC._gen3WildBattleWrapped then
    local origGCWild = GC.startWildBattle
    function GC.startWildBattle(world, species, level, game)
      local ok, err = startGen3Wild(world, species, level, game)
      if ok then return true end
      if type(origGCWild) == "function" then
        local ok2, a, b = pcall(origGCWild, world, species, level, game)
        if ok2 then return a, b end
      end
      return nil, err or "no wild battle adapter"
    end
    GC._gen3WildBattleWrapped = true
  end

  -- Sound softStub → real playCry; ambient capability already rides Gen1
  -- adapter remapping (GC.generation 3→1). Hoenn town ambient classify is
  -- a follow-up if map pools need allowlists.
  pcall(Gen3Compat.ensureSoundCryBridge)

  GC._gen3WildsHostArmed = true
  return true, "armed"
end


-- ----------------------------------------------------------- Encounter Radar
-- (engine-only; never edit AppData johto_radar)
--
-- Radar reads mod.content.encounters:get(mapId) and expects a Gen1-shaped
-- per-map record { grass={rate,slots,buckets}, water=... }. Gen3 stores
-- wilds under data.encounters.byMap as { land, water, fish } with
-- minLevel/maxLevel and NO cumulative buckets sized to slot count, and the
-- content registry routes to data.gen3Encounters (often unset on Ruby).
-- Publish Gen1-shaped tables via a content.encounters:get wrap; rods via
-- kind-keyed fishGroups + live map.fishGroup.

local RADAR_LAND_BUCKETS = { 20, 40, 50, 60, 70, 80, 85, 90, 94, 98, 99, 100 }
local RADAR_WATER_BUCKETS = { 60, 90, 95, 99, 100 }

local function radarBucketsFor(slots, preferred)
  local n = type(slots) == "table" and #slots or 0
  if n <= 0 then return nil end
  if type(preferred) == "table" and #preferred == n then return preferred end
  -- Uniform cumulative thresholds out of 100 when length mismatches.
  local out, step = {}, 100 / n
  for i = 1, n do
    out[i] = math.floor(step * i + 0.5)
  end
  out[n] = 100
  return out
end

local function radarSpeciesKey(game, species)
  if type(species) == "string" and species ~= "" then
    return species:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
  end
  local n = tonumber(species)
  if not n then return species end
  if type(game) == "table" and type(game.speciesName) == "function" then
    local ok, name = pcall(game.speciesName, game, n)
    if ok and type(name) == "string" and name ~= ""
        and not name:match("^POKeMON") and not name:match("^[?%-]+$") then
      return name:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]+", "")
    end
  end
  return n
end

local function radarKindFrom(game, info, bucketsPreferred)
  if type(info) ~= "table" or type(info.slots) ~= "table" or #info.slots == 0 then
    return nil
  end
  local slots = {}
  for _, s in ipairs(info.slots) do
    if type(s) == "table" and s.species ~= nil then
      local lo = tonumber(s.minLevel) or tonumber(s.level) or 2
      local hi = tonumber(s.maxLevel) or lo
      if hi < lo then hi = lo end
      -- Keep minLevel so multi-slot same-species tallies expand the range.
      slots[#slots + 1] = {
        species = radarSpeciesKey(game, s.species),
        level = lo,
        -- Stash max for callers that understand it; radar reads .level only.
        maxLevel = hi,
      }
    end
  end
  if #slots == 0 then return nil end
  local rate = tonumber(info.rate) or 25
  if rate < 0 then rate = 0 end
  return {
    rate = rate,
    slots = slots,
    buckets = radarBucketsFor(slots, bucketsPreferred),
  }
end

--- Gen3 byMap row → Gen1 per-map radar record (grass/water + Gen3 buckets).
function Gen3Compat.radarEncounterFor(game, mapId)
  if mapId == nil then return nil end
  -- Kind-keyed ids are handled by the get wrap, not here.
  if mapId == "fishGroups" or mapId == "grass" or mapId == "water"
      or mapId == "timeFishGroups" then
    return nil
  end
  local pack = game and game.data and game.data.encounters
  local byMap = pack and pack.byMap
  local row = nil
  if type(byMap) == "table" then
    row = byMap[mapId] or byMap[tostring(mapId)]
  end
  if type(row) ~= "table" and type(game) == "table"
      and type(game.encountersFor) == "function" then
    local map = { id = mapId }
    if type(game.lookupMapById) == "function" then
      local ok, found = pcall(game.lookupMapById, game, mapId)
      if ok and found then map = found end
    end
    local ok, enc = pcall(game.encountersFor, game, map)
    if ok then row = enc end
  end
  if type(row) ~= "table" then return nil end

  local grass = radarKindFrom(game, row.land or row.grass, RADAR_LAND_BUCKETS)
  local water = radarKindFrom(game, row.water, RADAR_WATER_BUCKETS)
  if not (grass or water) then return nil end
  return { grass = grass, water = water }
end

local function radarFishRodRows(game, slots, indexList, chanceList)
  local rows = {}
  for i, idx in ipairs(indexList) do
    local s = slots[idx]
    if type(s) == "table" and s.species ~= nil then
      local lo = tonumber(s.minLevel) or tonumber(s.level) or 5
      rows[#rows + 1] = {
        chance = chanceList[i] or 100,
        species = radarSpeciesKey(game, s.species),
        level = lo,
      }
    end
  end
  if #rows == 0 then return nil end
  return rows
end

--- One Gen2 kind-keyed fishGroups entry from a Gen3 fish table (10 slots).
function Gen3Compat.radarFishGroupFrom(game, fish)
  if type(fish) ~= "table" or type(fish.slots) ~= "table" or #fish.slots == 0 then
    return nil
  end
  local slots = fish.slots
  -- Gen3 chooseFishSlot weights out of 100, expressed as exclusive cum thresholds.
  local old = radarFishRodRows(game, slots, { 1, 2 }, { 70, 100 })
  local good = radarFishRodRows(game, slots, { 3, 4, 5 }, { 60, 80, 100 })
  local super = radarFishRodRows(game, slots, { 6, 7, 8, 9, 10 },
    { 40, 80, 95, 99, 100 })
  if not (old or good or super) then return nil end
  return {
    chance = tonumber(fish.rate) or 30,
    old = old, good = good, super = super,
  }
end

function Gen3Compat.radarFishGroups(game)
  if type(game) ~= "table" then return nil end
  if type(game._gen3RadarFishGroups) == "table" then
    return game._gen3RadarFishGroups
  end
  local byMap = game.data and game.data.encounters and game.data.encounters.byMap
  if type(byMap) ~= "table" then return nil end
  local out = {}
  for mapId, row in pairs(byMap) do
    if type(mapId) == "string" and type(row) == "table" then
      local group = Gen3Compat.radarFishGroupFrom(game, row.fish or row.fishing)
      if group then out[mapId] = group end
    end
  end
  game._gen3RadarFishGroups = out
  return out
end

--- Stamp fishGroup=mapId on the live map so radar's Gen2 rod path resolves.
function Gen3Compat.ensureMapFishGroup(game)
  if type(game) ~= "table" then return false end
  local map = game.map
  if type(map) ~= "table" or map.id == nil then return false end
  if map.fishGroup then return true end
  local groups = Gen3Compat.radarFishGroups(game)
  local id = map.id
  if type(groups) == "table" and (groups[id] or groups[tostring(id)]) then
    map.fishGroup = id
    return true
  end
  return false
end

local function clearRegistryCache(reg)
  if type(reg) ~= "table" or type(reg.cache) ~= "table" then return end
  for k in pairs(reg.cache) do reg.cache[k] = nil end
end

--- Wrap content.encounters (and optionally content.maps) for johto_radar.
function Gen3Compat.armRadarHost(loader)
  if Gen3Compat._radarHostArmed then return true, "already" end
  local content = loader
  if type(loader) == "table" and type(loader.content) == "table" then
    content = loader.content
  end
  if type(content) ~= "table" then return false, "no content" end
  local reg = content.encounters
  if type(reg) ~= "table" or type(reg.get) ~= "function" then
    return false, "no encounters registry"
  end
  if reg._gen3RadarWrapped then
    Gen3Compat._radarHostArmed = true
    return true, "already-wrapped"
  end

  local origGet = reg.get
  function reg.get(self, id)
    local g = nil
    if type(resolveGame) == "function" then
      local ok, got = pcall(resolveGame)
      if ok then g = got end
    end
    -- Alias Emerald routing target so base()/merges see byMap rows.
    if type(g) == "table" and type(g.data) == "table" then
      local pack = g.data.encounters
      if type(pack) == "table" and type(pack.byMap) == "table"
          and g.data.gen3Encounters == nil then
        g.data.gen3Encounters = pack.byMap
      end
    end
    if id == "fishGroups" then
      return Gen3Compat.radarFishGroups(g)
    end
    if id == "timeFishGroups" then return nil end
    local hit = Gen3Compat.radarEncounterFor(g, id)
    if hit ~= nil then return hit end
    return origGet(self, id)
  end
  reg._gen3RadarWrapped = true
  clearRegistryCache(reg)

  -- content.maps:get — inject fishGroup when the registry def lacks it.
  local maps = content.maps
  if type(maps) == "table" and type(maps.get) == "function"
      and not maps._gen3RadarFishWrapped then
    local origMapsGet = maps.get
    function maps.get(self, id)
      local def = origMapsGet(self, id)
      local g = nil
      if type(resolveGame) == "function" then
        local ok, got = pcall(resolveGame)
        if ok then g = got end
      end
      local groups = Gen3Compat.radarFishGroups(g)
      if type(def) == "table" and type(groups) == "table"
          and (groups[id] or groups[tostring(id)])
          and def.fishGroup == nil then
        -- Shallow copy so we do not mutate the cached registry value.
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        copy.fishGroup = id
        return copy
      end
      return def
    end
    maps._gen3RadarFishWrapped = true
    clearRegistryCache(maps)
  end

  -- Alias Emerald routing target. Do NOT set data.field.fishGroups: radar
  -- rodPages returns early whenever that table exists, even without a
  -- matching fishGroup, which would skip the kind-keyed fishGroups path.
  do
    local g = nil
    if type(resolveGame) == "function" then
      local ok, got = pcall(resolveGame)
      if ok then g = got end
    end
    if type(g) == "table" and type(g.data) == "table"
        and type(g.data.encounters) == "table"
        and type(g.data.encounters.byMap) == "table"
        and g.data.gen3Encounters == nil then
      g.data.gen3Encounters = g.data.encounters.byMap
    end
  end

  local Logger = package.loaded["src.core.Logger"]
  if Logger and Logger.info then
    pcall(Logger.info, "gen3 radar host: content.encounters wrapped for johto_radar")
  end
  Gen3Compat._radarHostArmed = true
  return true, "armed"
end


return Gen3Compat
