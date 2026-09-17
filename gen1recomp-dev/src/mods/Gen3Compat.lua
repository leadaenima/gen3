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

Gen3Compat.COVERAGE_VERSION = 5
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
--
-- The block-layer verbs ARE served as metatile shims (blockAt / setBlock /
-- tileAt / clearBlock) plus a pre-seeded dramaticShapeBlockHook, so the
-- DRAMATIC_SHAPE wrap no longer trips "has no Gen 3 backing" and a Cut tree
-- writes the grid the voxel mesher already reads.
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

  -- Pre-seeded so DRAMATIC_SHAPE's `if not Map.dramaticShapeBlockHook` read
  -- does not trip the __index warn. The mod stamps true after wrapping.
  Map.dramaticShapeBlockHook = false

  -- A map argument may be a raw Game3 map (.grid), a modMapView (.id), the
  -- Map module itself, or nil. Game3:modResolveMap is the same resolver the
  -- world view already uses for neighbours.
  local function rawMapOf(self)
    local g = live()
    if not g then
      if type(self) == "table" and type(self.grid) == "table" then return self end
      return nil
    end
    if type(g.modResolveMap) == "function" then
      local ok, found = pcall(g.modResolveMap, g, self)
      if ok and type(found) == "table" and type(found.grid) == "table" then
        return found
      end
    end
    if type(self) == "table" and type(self.grid) == "table" then return self end
    return g.map
  end

  -- The metatile at a CELL, border-extended the cartridge's way. Same
  -- contract as Game3ModWorld's view.blockAt so structure queries and the
  -- setBlock wrap's before/after read agree.
  function Map.blockAt(self, bx, by)
    if type(self) == "table" then
      local inst = rawget(self, "blockAt")
      if type(inst) == "function" and inst ~= Map.blockAt then
        local ok, id = pcall(inst, self, bx, by)
        if ok then return id end
      end
    end
    local map = rawMapOf(self)
    if not (map and type(map.grid) == "table") then return nil end
    bx = math.floor(tonumber(bx) or 0)
    by = math.floor(tonumber(by) or 0)
    local w, h = map.width or 0, map.height or 0
    if bx < 0 or by < 0 or bx >= w or by >= h then
      local border = map.border
      if type(border) ~= "table" or #border < 4 then return nil end
      local slot = (bx + 1) % 2 + ((by + 1) % 2) * 2
      return Game3.metatileOf(border[slot + 1])
    end
    return Game3.metatileOf(map.grid[by * w + bx + 1] or 0)
  end

  -- Emerald's Gen 3 tileAt: there is no 8px tile table, so the metatile id
  -- and the quadrant fold into one opaque art id.
  function Map.tileAt(self, tx, ty)
    tx = math.floor(tonumber(tx) or 0)
    ty = math.floor(tonumber(ty) or 0)
    local blockId = Map.blockAt(self, math.floor(tx / 2), math.floor(ty / 2)) or 0
    return blockId * 4 + (ty % 2) * 2 + (tx % 2)
  end

  -- Write a metatile. Elevation bits stay; an explicit impassable flag
  -- (Emerald setmetatile's fourth argument) updates collision. Out of
  -- bounds is a silent no-op, matching Gen 1 Map:setBlock.
  function Map.setBlock(self, bx, by, block, impassable)
    local map = rawMapOf(self)
    if not (map and type(map.grid) == "table") then return end
    local g = live()
    bx = math.floor(tonumber(bx) or 0)
    by = math.floor(tonumber(by) or 0)
    local i
    if g and type(g.gridIndex) == "function" then
      i = g:gridIndex(map, bx, by)
    else
      local w, h = map.width or 0, map.height or 0
      if bx >= 0 and by >= 0 and bx < w and by < h then
        i = by * w + bx + 1
      end
    end
    if not i then return end
    local cell = map.grid[i] or 0
    map.dirtyTiles = map.dirtyTiles or {}
    if map.dirtyTiles[i] == nil then map.dirtyTiles[i] = cell end
    local mid = tonumber(block) or 0
    local elev = Game3.elevationBits(cell)
    local col = Game3.collisionOf(cell)
    if impassable ~= nil then
      col = impassable and 1 or 0
    end
    local word = elev + (mid % 1024) + col * 1024
    if word == cell then return end
    map.grid[i] = word
    Game3.noteGridWrite(map)
    if g and type(g.markTilesDirty) == "function" then
      pcall(g.markTilesDirty, g, map)
    end
  end

  -- Drop a setBlock patch. Restores the cell recorded in dirtyTiles when
  -- one exists; otherwise a no-op (Ruby has no Gen 1 blockPatch table).
  function Map.clearBlock(self, bx, by)
    local map = rawMapOf(self)
    if not (map and type(map.grid) == "table") then return end
    local g = live()
    local i
    if g and type(g.gridIndex) == "function" then
      i = g:gridIndex(map, bx, by)
    else
      bx = math.floor(tonumber(bx) or 0)
      by = math.floor(tonumber(by) or 0)
      local w, h = map.width or 0, map.height or 0
      if bx >= 0 and by >= 0 and bx < w and by < h then
        i = by * w + bx + 1
      end
    end
    if not i then return end
    local prev = map.dirtyTiles and map.dirtyTiles[i]
    if prev == nil then return end
    map.grid[i] = prev
    map.dirtyTiles[i] = nil
    Game3.noteGridWrite(map)
    if g and type(g.markTilesDirty) == "function" then
      pcall(g.markTilesDirty, g, map)
    end
  end

  return setmetatable(Map, {
    __index = function(_, key)
      warnOnce("map." .. tostring(key),
        "src.world.Map.%s has no Gen 3 backing: Ruby has metatiles and no "
        .. "block table, so only the map-type questions and the metatile "
        .. "shims (blockAt/setBlock) carry over",
        tostring(key))
      return nil
    end,
    __newindex = function(t, key, value) rawset(t, key, value) end,
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
      renderer = "thin setWorldOverride seam onto Game3.worldOverride; "
        .. "Game3:draw presents it behind the battle UI (Emerald endFrame "
        .. "parity). Not a full two-pass Renderer",
    },
  },
  ["src.world.Map"] = {
    kind = "facade",
    target = "src/core/Game3.lua map-type readers + metatile grid",
    backed = "isOutdoor isOutside blockAt tileAt setBlock clearBlock "
      .. "dramaticShapeBlockHook",
    absent = "new",
    notes = {
      isOutdoor = "the GBA header stores a map type, so this is read rather "
        .. "than inferred from a tileset name the way Gen 1 does it",
      new = "there is no Gen 3 map object for it to construct; read the "
        .. "active map through mod.world:mapView()",
      blockAt = "metatile id at a cell (border-extended); same answer as "
        .. "Game3ModWorld view.blockAt",
      tileAt = "Emerald Gen 3 fold: metatile * 4 + quadrant -- an opaque "
        .. "art id, not a Gen 1 block-table index",
      setBlock = "writes a metatile through map.grid, preserves elevation, "
        .. "honours optional impassable; noteGridWrite + dirtyTiles",
      clearBlock = "restores the dirtyTiles snapshot when one exists",
      dramaticShapeBlockHook = "pre-seeded false so the mod's marker read "
        .. "does not warn; the mod stamps true after wrapping setBlock",
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
  ["src.ui.Screens"] = {
    kind = "adapter",
    target = "Game3:openStartMenu (Ruby's menus are field states, not a stack)",
    backed = "push",
    warned = "pop",
    notes = {
      push = "\"StartMenu\" opens Ruby's own start menu; any other screen is "
        .. "refused with a logged reason, because Ruby has no screen stack",
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
-- states stepped by Game3. A mod reaching for it gets Gen 1's module and Gen
-- 1's screens, and the voxel mod does exactly that -- its free walk handles
-- START with `Screens.push(Game, "StartMenu")`, which built Gen 1's start menu
-- over Ruby, read `game.party` as a Gen 1 table, and crashed the moment START
-- was pressed in first person.
--
-- Served here so the one screen Ruby genuinely has means Ruby's version of
-- it. Everything else is refused out loud: pretending to push a screen that
-- does not exist would leave a mod waiting on a prompt nobody drew.
local SCREENS_UNBACKED = {
  HordeExitPrompt = "Ruby has no screen stack to push a mod prompt onto; its "
    .. "menus are Game3 field states",
  HordeGameOver = "Ruby has no screen stack to push a mod prompt onto; its "
    .. "menus are Game3 field states",
}

local function buildScreens()
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
  function Screens.push(_, name)
    if name == "StartMenu" then
      local g = game()
      if not g then return nil end
      -- A START PRESS IN THIS LOGIC STEP IS THE ENGINE'S, AND IT HAS ALREADY
      -- ACTED ON IT. Game3:logicStep runs its START / field chain before
      -- walkHeld, so by the time a replaced walk sees the press the menu has
      -- been opened -- or, if it was up, CLOSED by stepField. Honouring the
      -- request then would reopen the menu the player just shut: START could
      -- never close it in first person. The crash this adapter replaces was
      -- that same second handling, reaching Gen 1's start menu instead.
      local okI, Input = pcall(require, "src.core.Input")
      if okI and Input and Input.wasPressed and Input:wasPressed("start") then
        return true
      end
      return g:openStartMenu()
    end
    local key = tostring(name)
    if not warned[key] then
      warned[key] = true
      Logger.info("gen3 facade: src.ui.Screens.push(%s) has no Gen 3 screen: %s",
        key, SCREENS_UNBACKED[key] or "Ruby has no screen stack")
    end
    return nil
  end
  -- popping is Ruby's own menu code's business; a mod has nothing to pop
  function Screens.pop() return nil end
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
      if which == "back" then
        local bx, by, bs = BattleState.backPlacement(w, h, 0, 0, scale)
        px, py, scale = (bx or 0) + sx, (by or 0) + sy, bs or scale
      else
        local ok, tx, ty = pcall(host.battlerTopLeft, host, side, mon.species, which)
        local ex = (ok and tx) or 0
        local ey = (ok and ty) or 0
        local fx, fy, fs = BattleState.frontPlacement(ex, ey, w, h, scale)
        px, py, scale = (fx or ex) + sx, (fy or ey) + sy, fs or scale
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

  local function asBattle(host)
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
  ["src.battle.BattleState"] = buildBattleState,
}

Gen3Compat.ADAPTERS = ADAPTERS

function Gen3Compat.bind(fn)
  resolveGame = fn
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

return Gen3Compat
