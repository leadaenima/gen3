-- MODS ON RUBY.
--
-- Gen 1 and Gen 2 each build a ModLoader in their own load(); Game3 never did,
-- so Ruby -- the most complete engine in this tree -- was the one game that
-- loaded no mods at all. This suite pins the four pieces that changed it:
--
--   * the loader is constructed on a Ruby boot, with the game as its owner;
--   * a mod is gated on claiming a Gen 3 game, so one written for Red is
--     listed and skipped rather than half-applied;
--   * every content registry is gated on Gen 3 EXCEPT render_pipelines, so a
--     content mod reports "no Gen 3 target" instead of merging a Red-shaped
--     record into a Hoenn table;
--   * the world pass goes through Pipelines, which is the half that is inert
--     on Gold and is not inert here.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
local ModTargets = require("src.mods.ModTargets")
local GameVersion = require("src.core.GameVersion")
local Game3 = require("src.core.Game3")

local S = require("tests.harness").suite("ruby mods")
local check, eq = S.check, S.eq

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

-- ------------------------------------------------- Ruby is a mod target
--
-- ModTargets derives everything from GameVersion.ORDER, so it needed no Gen 3
-- branch -- but only if Ruby is actually in that list at generation 3. It is,
-- which is why a manifest can say "ruby" or "gen3" and be understood.
eq(GameVersion.generation("ruby"), 3, "ruby is a Gen 3 game")
eq(table.concat(ModTargets.generationVersions(3), ","), "ruby",
  "and the only one this engine has")
eq(table.concat(ModTargets.expand("gen3") or {}, ","), "ruby",
  '"gen3" in a manifest expands to it')
eq(table.concat(ModTargets.expand("ruby") or {}, ","), "ruby",
  "and so does naming it outright")
-- `games` on a VALIDATED manifest holds version ids, not the tokens the
-- author wrote: Manifest.validate expands "gen3" through ModTargets.normalize
-- at load. Handing supports() a raw token instead is not a weaker test, it is
-- a different one -- GameVersion.generation has no entry for "gen3" and the
-- call throws.
eq(table.concat(ModTargets.normalize({ "gen3" }), ","), "ruby",
  "a manifest saying gen3 normalizes to the ruby id")
check(ModTargets.supports({ games = { "ruby" } }, nil, 3),
  "a manifest claiming Ruby supports a Gen 3 boot")
check(not ModTargets.supports({ games = { "red" } }, nil, 3),
  "a Red-only one does not")
-- the pre-`games` reading: Gen 1 always, Gen 2 on the compat flag, Gen 3
-- never -- a mod written before Ruby existed cannot have meant Ruby
check(not ModTargets.supports({}, nil, 3),
  "a manifest with no games key does not silently claim Ruby")
check(not ModTargets.supports({ gen2compat = true }, nil, 3),
  "and neither does gen2compat -- that flag is about Gold")

-- ------------------------------------------- the Gen 3 registry routing
--
-- Ruby's tables are the GBA cartridge's layout, read through Game3, which is a
-- separate game object from Gen 1's. So a registry's Gen 1 target is not
-- automatically a Gen 3 target, and routing one whose shape has not been
-- checked would merge a Red-shaped record into a Hoenn table and report
-- success. The table is therefore gated by default.
do
  local total, gated = 0, 0
  for name in pairs(Schemas.REGISTRIES) do
    total = total + 1
    if Schemas.gatedFor(name, 3) then gated = gated + 1 end
  end
  check(total > 40, "the catalog is the full one, not a stub")
  eq(gated, total - 1, "every registry but one is gated on Gen 3")
end
check(not Schemas.gatedFor("render_pipelines", 3),
  "render_pipelines is the exception: Game3:load installs Pipelines on the "
  .. "merged data, so data.render_pipelines is the table it reads")
eq(Schemas.targetFor("render_pipelines", Schemas.REGISTRIES.render_pipelines, 3),
  "render_pipelines", "and it keeps the shared target rather than a Gen 3 one")
-- a few named ones, so the gate is not just a count
check(Schemas.gatedFor("pokemon", 3), "pokemon is gated (Gen 3 record shape)")
check(Schemas.gatedFor("maps", 3), "maps is gated (Gen3MapPack owns them)")
check(Schemas.gatedFor("transitions", 3),
  "transitions is gated -- Ruby's are Game3BattleTransition, not data.transitions")

-- the other two generations are untouched by any of this
eq(Schemas.targetFor("maps", Schemas.REGISTRIES.maps, 2), "gen2Maps",
  "Gold still routes maps to gen2Maps")
eq(Schemas.targetFor("maps", Schemas.REGISTRIES.maps, 1),
  Schemas.REGISTRIES.maps.target, "and Red still uses the catalog target")
check(not Schemas.gatedFor("pokemon", 1), "nothing new is gated on Red")
check(not Schemas.gatedFor("pokemon", 2), "nor on Gold")

-- ------------------------------------------- the loader on a Ruby boot
--
-- generation is fixed at construction from GameVersion, so a Ruby boot builds
-- a generation-3 loader without anyone passing it one.
do
  local was = GameVersion.get()
  GameVersion.set("ruby")
  local l = Loader.new({ fs = memfs({}) })
  eq(l.generation, 3, "a loader built during a Ruby boot is generation 3")
  GameVersion.set(was)
end

-- a mod that claims Gen 3 runs; one that claims Gen 1 is listed and skipped
do
  local was = GameVersion.get()
  GameVersion.set("ruby")
  local files = {
    ["mods/hoenn/manifest.json"] = [[{
      "id": "hoenn", "name": "Hoenn Mod", "version": "1.0.0", "api": 2,
      "entry": "main.lua", "games": ["gen3"] }]],
    ["mods/hoenn/main.lua"] = "return function() end",
    ["mods/kanto/manifest.json"] = [[{
      "id": "kanto", "name": "Kanto Mod", "version": "1.0.0", "api": 2,
      "entry": "main.lua", "games": ["gen1"] }]],
    ["mods/kanto/main.lua"] = "return function() end",
  }
  local l = Loader.new({ fs = memfs(files) })
  local ok = pcall(function() l:load({}) end)
  check(ok, "the loader runs against a Gen 3 boot")
  local byId = {}
  for _, row in ipairs((l:status() or {}).available or {}) do
    byId[row.id] = row
  end
  check(byId.hoenn ~= nil, "the Gen 3 mod is discovered")
  check(byId.kanto ~= nil, "so is the Gen 1 one -- skipped is not hidden")
  eq((byId.hoenn or {}).state, "loaded",
    "the mod that claims Gen 3 actually runs on Ruby")
  eq((byId.kanto or {}).state, "wrong_generation",
    "and the Gen 1 one is refused for the right reason")
  -- the manager shows this line, so it has to name the game rather than
  -- leaving the player to guess why nothing happened
  eq((byId.kanto or {}).note, "For Gen 1, not Ruby",
    "with a note that says which game it was made for and which this is")
  GameVersion.set(was)
end

-- ---------------------------------------- Game3 publishes what it must
--
-- The loader's own docs are explicit that without an owner the mod facade
-- binds to the Gen 1 src/core/Game.lua singleton -- which a Ruby boot never
-- loads, main.lua having branched to Game3 instead. So Game3:load has to set
-- it, and the manager needs three more names Game3 did not previously carry.
check(type(Game3.openModManager) == "function", "Ruby can open the manager")
check(type(Game3.stepModManager) == "function", "and step it")
check(type(Game3.drawModManager) == "function", "and draw it")
check(type(Game3.writeOptions) == "function",
  "and persist what it changed -- ManagerState calls game:writeOptions")
check(type(Game3.modOptionsStore) == "function",
  "the shared options file is held once, not copied per read")
;(function()
  local g = Game3.new()
  local store = g:modOptionsStore()
  check(type(store) == "table", "the options store resolves even with no file")
  check(g.save ~= nil and g.save.options == store,
    "and is published at game.save.options, where ManagerState reads it")
  eq(g:modOptionsStore(), store, "the second call hands back the same table")
end)()

-- ------------------------------------------------------- the MODS row
--
-- Gated on at least one DISCOVERED mod, the way Red's and Gold's rows are, so
-- a vanilla install's START menu is the cartridge's own.
;(function()
  local g = Game3.new()
  g.party = {}
  local function labels()
    local out = {}
    for _, name in ipairs(g:startMenuItems()) do out[name] = true end
    return out
  end
  check(not g:hasMods(), "a boot that discovered nothing has no mods")
  check(not labels().MODS, "so the START menu has no MODS row")
  g.modStatus = { available = {} }
  check(not labels().MODS, "an empty discovery list is still no row")
  g.modStatus = { available = { { id = "hoenn" } } }
  check(g:hasMods(), "one discovered mod is enough")
  check(labels().MODS, "and the row appears")
  -- it sits after OPTION and before the row that closes the menu, which is
  -- where both other games put it
  local items = g:startMenuItems()
  local optionAt, modsAt, exitAt
  for i, name in ipairs(items) do
    if name == "OPTION" then optionAt = i end
    if name == "MODS" then modsAt = i end
    if name == "EXIT" then exitAt = i end
  end
  check(optionAt and modsAt and exitAt, "all three rows are present")
  check(optionAt < modsAt, "MODS comes after OPTION")
  check(modsAt < exitAt, "and before EXIT")
end)()

-- SAFARI mode's menu is the cartridge's own short list and takes no MODS row:
-- it is a different menu, not the normal one with rows hidden.
;(function()
  local g = Game3.new()
  g.modStatus = { available = { { id = "hoenn" } } }
  g.inSafariMode = function() return true end
  for _, name in ipairs(g:startMenuItems()) do
    check(name ~= "MODS", "the SAFARI menu carries no MODS row")
  end
end)()

-- ------------------------------------------------- the render pipeline
--
-- This is the half that is inert on Gold -- Schemas.lua says so in those words,
-- because Gold's overworld draws straight to the window. Ruby already paints
-- the world into a canvas for TILT, so a pipeline that replaces the world pass
-- has somewhere to draw.
check(type(Game3.drawWorldFlat) == "function",
  "the cartridge's own world pass is reachable, for ctx.fallback")
check(type(Game3.worldPipelineId) == "function",
  "and there is one answer to whether a pipeline owns the world")
check(type(Game3.worldPipelineContext) == "function", "and a context to hand it")

;(function()
  local g = Game3.new()
  -- with no pipeline registered the world draws the cartridge's way
  local flat = 0
  g.drawWorldFlat = function() flat = flat + 1 end
  g.worldPipelineId = function() return nil end
  g:drawWorldBody(1)
  eq(flat, 1, "no pipeline means the flat pass runs")
end)()

;(function()
  -- a pipeline that returns a canvas owns the frame
  local Pipelines = require("src.render.Pipelines")
  local g = Game3.new()
  local flat, drew = 0, 0
  g.drawWorldFlat = function() flat = flat + 1 end
  g.worldPipelineId = function() return "voxel" end
  -- a real Canvas can always be measured, and the present step now needs
  -- that: the image comes back in PHYSICAL pixels and has to be scaled onto
  -- a playfield counted in logical units
  local canvas = { _canvas = true,
    getPixelWidth = function() return 720 end,
    getPixelHeight = function() return 1280 end }
  local realDraw, realPresent = Pipelines.drawWorld, Pipelines.worldPresent
  local realG = love.graphics.draw
  Pipelines.drawWorld = function() return canvas end
  Pipelines.worldPresent = function(c) return c end
  love.graphics.draw = function() drew = drew + 1 end
  g:drawWorldBody(1)
  love.graphics.draw = realG
  Pipelines.drawWorld, Pipelines.worldPresent = realDraw, realPresent
  eq(flat, 0, "a pipeline that draws replaces the cartridge's pass")
  eq(drew, 1, "and its canvas is what reaches the screen")
end)()

;(function()
  -- a pipeline that declines falls back rather than leaving the world blank
  local Pipelines = require("src.render.Pipelines")
  local g = Game3.new()
  local flat = 0
  g.drawWorldFlat = function() flat = flat + 1 end
  g.worldPipelineId = function() return "voxel" end
  local realDraw = Pipelines.drawWorld
  Pipelines.drawWorld = function() return nil end
  g:drawWorldBody(1)
  Pipelines.drawWorld = realDraw
  eq(flat, 1, "a declining pipeline falls through to the flat pass")
end)()

;(function()
  -- and one that throws must not take the frame down
  local Pipelines = require("src.render.Pipelines")
  local g = Game3.new()
  local flat = 0
  g.drawWorldFlat = function() flat = flat + 1 end
  g.worldPipelineId = function() return "voxel" end
  local realDraw = Pipelines.drawWorld
  Pipelines.drawWorld = function() error("mod blew up") end
  local ok = pcall(g.drawWorldBody, g, 1)
  Pipelines.drawWorld = realDraw
  check(ok, "a throwing pipeline does not take the frame down")
  eq(flat, 1, "and the world still draws")
end)()

-- The context carries the names Gen 1's pipelines expect, so a mod written
-- against that engine finds what it reaches for.
;(function()
  local g = Game3.new()
  g.camX, g.camY = 40, 80
  g.viewW, g.viewH = 240, 160
  local ctx = g:worldPipelineContext(2, nil)
  eq(ctx.game, g, "the game is in the context")
  eq(ctx.scale, 2, "so is the scale")
  eq(ctx.camX, 40, "and the camera")
  eq(ctx.cam.x, 40, "under both spellings Gen 1 uses")
  eq(ctx.cam.y, 80, "both axes")
  eq(ctx.width, 240, "and the viewport")
  eq(ctx.height, 160, "both dimensions")
  eq(ctx.generation, 3, "and which generation is asking")
  check(type(ctx.fallback) == "function",
    "a pipeline can ask for the cartridge's own world back")
  -- the SGB palette hooks answer nil rather than inventing a palette: Ruby's
  -- art is true-colour GBA and is never re-mapped
  eq(ctx.paletteFor(), nil, "no SGB world palette on Ruby")
  eq(ctx.spriteColors(), nil, "nor sprite colours")
end)()

-- A world pipeline outranks TILT: both want to own the world pass, and
-- without this the diorama would be drawn and then thrown away by the tilt
-- capture. Gen 1 gates the same way.
;(function()
  local src = io.open("src/core/Game3.lua", "r")
  local body = src and src:read("*a") or ""
  if src then src:close() end
  check(body:find("not self:worldPipelineId()", 1, true) ~= nil,
    "the tilt gate asks whether a pipeline owns the world first")
end)()


-- ------------------------------------------- the round trip, end to end
--
-- Through stepField, not by calling the helpers: the first version of this
-- closed the manager back to a field of kind "start", which LOOKS right and
-- is not -- stepField gates the START menu on the exact string "menu", so the
-- menu came back drawn but inert. Only walking the real input path showed it.
;(function()
  local Input = require("src.core.Input")
  local g = Game3.new()
  g.party = {}
  g.modStatus = { available = { { id = 'voxel', name = 'Voxel',
    version = '0.7.40', state = 'loaded' } } }
  g.playerName = function() return 'BRENDAN' end
  local function press(k)
    local old = Input.wasPressed
    Input.wasPressed = function(_, x) return x == k end
    local ok = pcall(function() g:stepField() end)
    Input.wasPressed = old
    return ok
  end

  g.field = { kind = 'menu', cursor = g:startMenuIndex('MODS') }
  eq(g:startMenuItems()[(g.field.cursor or 0) + 1], 'MODS',
    'startMenuIndex finds the MODS row')
  check(press('a'), 'A on it does not throw')
  eq(g.field.kind, Game3.MODS_FIELD, 'and opens the manager')
  check(g.stack ~= nil and #g.stack.states == 1,
    'with exactly the manager on its stack')
  check(press('b'), 'B does not throw either')
  eq(g.field.kind, 'menu',
    'and lands back on the START menu -- the kind stepField actually gates on')
  eq(g:startMenuItems()[(g.field.cursor or 0) + 1], 'MODS',
    'with the cursor still on the row it was opened from')
  check(g.stack ~= nil and g.stack.top ~= nil,
    'and the standing mod stack is back -- closing used to null it, which '
    .. 'stranded any mod that captured game.stack at boot')
end)()


-- --------------------------------------------- the Gen 3 mod facade
--
-- A mod asks for the module names the Gen 1 engine publishes, because those
-- are the names the mod API documents. Gen2Compat answers them with Gold's
-- equivalents on a Gold boot; Gen3Compat is that job for Ruby.
--
-- The bug this replaced is the reason the file exists. The loader's
-- interposition read `generation ~= 1`, written when Gen 2 was the only other
-- generation -- so once Ruby arrived, a Gen 3 mod asking for src.core.Game
-- was handed GOLD's adapter and src.world.Map was handed src.world.gen2.Map.
-- Live, working modules of a game that is not running: the mod reads an empty
-- world off them with no way to tell why. A refusal beats a plausible wrong
-- answer.
local Gen2Compat = require("src.mods.Gen2Compat")
local Gen3Compat = require("src.mods.Gen3Compat")

check(Gen2Compat.serves("src.world.Map"),
  'Gen2Compat still serves src.world.Map -- Gold is unchanged')
-- Both arms serve the NAME; what matters is that they resolve to different
-- things. Gold's points at src.world.gen2.Map; Ruby's is its own adapter over
-- Game3's map-type readers, because Ruby has metatiles and no block table.
check(Gen3Compat.serves("src.world.Map"),
  "Gen3Compat serves src.world.Map with an arm of its own")
check(Gen2Compat.ADAPTERS["src.world.Map"] ~= Gen3Compat.ADAPTERS["src.world.Map"],
  "and it is NOT Gold's -- the two resolve to different adapters")
eq(Gen2Compat.ADAPTERS["src.world.Map"], "src.world.gen2.Map",
  "Gold's is still the gen2 module")
check(type(Gen3Compat.ADAPTERS["src.world.Map"]) == "function",
  "Ruby's is built, not aliased to another generation's module")
check(Gen3Compat.serves("src.core.Game"),
  "the one name it does serve is src.core.Game -- 33 of the voxel mod's" ..
  'requires are that')

-- coverage is the honest statement of how far it goes, in Gen2Compat's own
-- three states, so an author can see what a name will do before running it
;(function()
  local row = Gen3Compat.coverage("src.core.Game")
  check(row ~= nil, 'src.core.Game has a coverage row')
  eq(row.kind, 'facade', 'and it is a facade, never an alias')
  eq(Gen3Compat.memberStatus("src.core.Game", 'data'), 'backed',
    '.data is the real merged dataset')
  eq(Gen3Compat.memberStatus("src.core.Game", 'save'), 'warned',
    ".save is usable but is not a Gen 1 save struct, so it is warned " ..
    'rather than claimed as backed')
  -- .overworld was absent while nothing built the shape; it is backed now
  -- that src/core/Game3ModWorld.lua does. What did NOT change is the rule
  -- underneath: a field is backed only when it reads live state, never
  -- because a plausible value could be supplied for it.
  eq(Gen3Compat.memberStatus("src.core.Game", 'overworld'), 'backed',
    '.overworld is a constructed shape over the live Game3')
  eq(Gen3Compat.memberStatus("src.core.Game", 'renderer'), 'absent',
    'and no Renderer holding a world override')
  eq(Gen3Compat.COVERAGE_VERSION, Gen2Compat.COVERAGE_VERSION,
    'both arms publish the same coverage contract version')
end)()

-- The facade reads the LIVE game every time. A mod that captured Game at load
-- and reads .data a minute later must see the data the game has now, so this
-- cannot be a snapshot taken when the table was built.
;(function()
  local g = Game3.new()
  g.data = { pokemon = { 'first' } }
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve("src.core.Game", 'test')
  eq(Game.data, g.data, '.data is the live table')
  eq(Game.options, g.options, 'so are the options')
  check(Game.input ~= nil, 'and there is an input source')
  check(Game.save ~= nil and Game.save.options ~= nil,
    '.save carries the shared launcher options the manager reads')
  eq(type(Game.writeOptions), 'function', 'writeOptions is callable')
  -- the late-binding check: replace the table the game holds
  local second = { pokemon = { 'second', 'third' } }
  g.data = second
  eq(Game.data, second,
    "replacing the game's data is visible through the facade -- it resolves " ..
    'per read, not once at build')
end)()

-- Methods forward bound to the live instance, so Game.foo() reaches
-- Game3:foo() rather than calling it with no self.
;(function()
  local g = Game3.new()
  g.party = {}
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve("src.core.Game", 'test')
  eq(type(Game.startMenuItems), 'function', 'a Game3 method comes through')
  local ok, items = pcall(Game.startMenuItems)
  check(ok, 'calling it with no explicit self works')
  check(type(items) == 'table' and #items > 0,
    'and it returns what the method returns')
end)()

-- The names with no Gen 3 shape answer nil AND say why, rather than nil in
-- silence -- which is the difference between a mod author finding the gap in
-- a log line and finding it in a blank screen.
;(function()
  local g = Game3.new()
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve("src.core.Game", 'test')
  check(Game.overworld ~= nil,
    '.overworld is served now -- a constructed shape over live state')
  eq(Game.renderer, nil,
    'but .renderer is still nil, not fabricated: Ruby draws the world in '
    .. 'Game3:drawWorldBody with no Renderer holding an override')
  local notes = Gen3Compat.coverage("src.core.Game").notes
  check(notes.overworld ~= nil and #notes.overworld > 0,
    "with a note saying Game3 IS the world, so an author knows where to look")
end)()

-- ------------------------------ reaching into another generation's engine
--
-- This used to fire on Gen 1 only, which left the hole open the moment there
-- were three generations: on a Ruby boot a mod could require src.core.Game2
-- and get Gold's live modules. The reason is the same whichever way it points
-- -- the structs are not this game's -- so it is stated once and applied to
-- every generation but the module's own.
;(function()
  local Sandbox = require("src.mods.Sandbox")
  check(Sandbox ~= nil, 'the sandbox module loads')
end)()
-- Behaviourally, not by grepping the source: the first version of this read
-- the loader's text for the table name, so gutting the loop that uses it
-- still passed. What matters is that the require is actually refused -- and
-- the sandbox has its own _G, so the observable is the mod's load state, not
-- a global the chunk sets.
;(function()
  local was = GameVersion.get()
  GameVersion.set('ruby')
  local function modFiles(id, target)
    return {
      ['mods/' .. id .. '/manifest.json'] = ('{ "id": "%s", "name": "%s", '
        .. '"version": "1.0.0", "api": 2, "entry": "main.lua", '
        .. '"games": ["ruby"], "permissions": ["engine_internals"] }')
        :format(id, id),
      ['mods/' .. id .. '/main.lua'] =
        ('require("%s") return function() end'):format(target),
    }
  end

  -- reaching into GOLD's engine from a Ruby boot
  local l2 = Loader.new({ fs = memfs(modFiles('reachgen2', 'src.core.Game2')) })
  pcall(function() l2:load({}) end)
  local row2
  for _, r in ipairs((l2:status() or {}).available or {}) do
    if r.id == 'reachgen2' then row2 = r end
  end
  check(row2 ~= nil, 'the reaching mod is discovered')
  check(row2 and row2.state ~= 'loaded',
    "a Ruby mod requiring src.core.Game2 does not load -- it is refused "
    .. "rather than handed Gold's engine")
  local said = table.concat({ tostring(row2 and row2.note),
    tostring(row2 and row2.error), tostring(row2 and row2.message) }, ' ')
  for _, e in ipairs((l2:status() or {}).errors or l2.errors or {}) do
    said = said .. ' ' .. tostring(type(e) == 'table' and e.message or e)
  end
  check(said:find('Gen 2 engine module', 1, true) ~= nil,
    'and is told which generation it reached into')
  check(said:find('Gen 3 game', 1, true) ~= nil,
    'and which one it is actually running on')

  -- its OWN generation's engine is not refused
  local l3 = Loader.new({ fs = memfs(modFiles('reachgen3', 'src.core.Game3')) })
  pcall(function() l3:load({}) end)
  local row3
  for _, r in ipairs((l3:status() or {}).available or {}) do
    if r.id == 'reachgen3' then row3 = r end
  end
  check(row3 and row3.state == 'loaded',
    "while src.core.Game3 on a Ruby boot is the mod's own engine and passes")
  GameVersion.set(was)
end)()

;(function()
  local f = io.open('src/mods/Loader.lua', 'r')
  local body = f and f:read('*a') or ''
  if f then f:close() end
  check(body:find('GENERATION_MODULES', 1, true) ~= nil,
    'the rule is a table, so a fourth generation adds a row and nothing else')
  -- the contract, and a future generation adds a row to it and nothing else
  local f = io.open("src/mods/Loader.lua", 'r')
  local body = f and f:read('*a') or ''
  if f then f:close() end
  check(body:find('GENERATION_MODULES', 1, true) ~= nil,
    'the cross-generation rule is a table, not a hard-coded generation')
  check(body:find('src.core.Game3', 1, true) ~= nil,
    "and it names Game3, so Red and Gold refuse Ruby's engine too")
  check(body:find('devShim.generation == 2 and Gen2Compat.serves(name)', 1, true)
    == nil, 'the facade gate is no longer a bare Gen 2 test')
  check(body:find('facadeFor(devShim.generation)', 1, true) ~= nil,
    'it asks which facade this generation has')
end)()


-- ------------------------------------------------ mod.world on Ruby
--
-- `mod.world` is the route the loader's own error messages point authors at.
-- Until src/world/gen3/WorldAPI.lua existed it LIED on Ruby: Loader:_modApi
-- resolved the arm with `generation == 2 and gen2 or gen1`, so a Gen 3 boot
-- fell through to Red's WorldAPI wrapped around a Game3 instance -- every call
-- finding nil where it looked for game.overworld, indistinguishable from an
-- empty map. Same bug shape as the require interposition's old `~= 1` gate,
-- in two more places.
local WorldAPI3 = require('src.world.gen3.WorldAPI')

-- A 4x3 fixture whose three planes occupy DISJOINT value ranges, so a reader
-- that returns the wrong field cannot accidentally look right.
--
-- The first version used `i + (i % 2) * 1024 + (i % 4) * 4096`, where
-- collision and elevation happen to be equal at exactly the cells the
-- assertions checked -- so swapping elevationOf for collisionOf passed clean.
-- Here metatiles are 101..112, collision is 0 or 1, and elevation is 5..8:
-- no two planes can share a value.
local function fixtureGame()
  local g = Game3.new()
  local grid = {}
  for i = 1, 12 do
    grid[i] = (100 + i) + (i % 2) * 1024 + (5 + i % 4) * 4096
  end
  g.map = { id = 'TESTMAP', width = 4, height = 3, grid = grid,
    border = { 5, 6, 7, 8 }, mapType = Game3.MAP_TYPE_ROUTE }
  g.playerX, g.playerY, g.facing = 2, 1, 'south'
  return g
end

;(function()
  local g = fixtureGame()
  local w = WorldAPI3.new(g, 'test')
  local cur = w:current()
  eq(cur.mapId, 'TESTMAP', 'current() names the active map')
  eq(cur.x, 2, 'and the player x')
  eq(cur.y, 1, 'and y')
  eq(cur.facing, 'south', 'and facing')

  -- fieldmap.c packs all three into one 16-bit word; these are its masks
  eq(w:metatileAt(0, 0), 101, 'metatile is bits 0-9')
  eq(w:collisionAt(0, 0), 1, 'collision is bits 10-11')
  eq(w:elevationAt(0, 0), 6, 'elevation is bits 12-15 -- 6, not the 1 '
    .. 'collision reads, so a swap of the two cannot pass')
  eq(w:metatileAt(3, 2), 112, 'the last cell reads from the end of the grid')
  eq(w:elevationAt(3, 2), 5, 'and its elevation is 5 while its collision is 0')

  -- out of bounds is an error, not a clamp: the cartridge border-extends and
  -- a caller that wants that has to ask for it by name
  local v, why = w:metatileAt(4, 0)
  eq(v, nil, 'reading past the right edge fails')
  eq(why, 'cell out of bounds', 'and says so rather than clamping')
  eq(select(2, w:metatileAt(0, -1)), 'cell out of bounds', 'same above')
  eq(select(2, w:metatileAt(1.5, 0)), 'invalid cell coordinates',
    'and a fractional coordinate is refused outright')

  -- GetBorderBlockAt wraps a 2x2 patch: (x+1)&1 + ((y+1)&1)*2
  eq(w:borderMetatileAt(-1, -1), 5, 'the border patch indexes by parity')
  eq(w:borderMetatileAt(0, -1), 6, 'x parity picks the next entry')
  eq(w:borderMetatileAt(-1, 0), 7, 'y parity steps a row')
  eq(w:borderMetatileAt(0, 0), 8, 'and both together the fourth')

  -- one cell read three ways: the planes are disjoint by construction, so
  -- all three answers differing is the check that they are separate fields
  local mt, col, elev = w:metatileAt(1, 1), w:collisionAt(1, 1), w:elevationAt(1, 1)
  check(mt ~= col and col ~= elev and mt ~= elev,
    'metatile, collision and elevation are three different fields of one word')
  check(mt >= 101 and mt <= 112, 'the metatile is in the metatile range')
  check(col == 0 or col == 1, 'the collision is in the collision range')
  check(elev >= 5 and elev <= 8, 'and the elevation in its own')
end)()

-- no map, no world: during the boot cinema and the title there is nothing to
-- read, and answering the game anyway would hand back a live-looking object
;(function()
  local g = Game3.new()
  g.map = nil
  local w = WorldAPI3.new(g, 'test')
  eq(w:overworld(), nil, 'a game with no map is not a world')
  eq(select(2, w:current()), 'no overworld', 'and current() says which')
  eq(select(2, w:mapView()), 'no overworld', 'so does mapView()')
end)()

-- the map view: the shape a renderer walks
;(function()
  local g = fixtureGame()
  local w = WorldAPI3.new(g, 'test')
  local mv = w:mapView()
  check(mv ~= nil, 'the active map has a view')
  eq(mv.width, 4, 'its width')
  eq(mv.height, 3, 'and height')
  eq(#mv.metatileCells, 12, 'one metatile per cell')
  eq(#mv.collisionCells, 12, 'one collision value per cell')
  eq(#mv.elevationCells, 12, 'and one elevation per cell -- the Y axis Gen 2 '
    .. 'records nowhere at all')
  eq(mv.elevationCells[1], 6, 'row-major order, first cell')
  eq(mv.elevationCells[12], 5, 'and last')
  -- A Gen 3 metatile is 16x16 and IS one collision cell; a Gen 1/2 block is
  -- 32x32 holding four. A renderer reads these instead of asking which game.
  eq(mv.blockTiles, 2, 'a Gen 3 block is two 8px tiles on a side')
  eq(mv.blockCells, 1, 'and one collision cell, not four')
  eq(mv.outdoor, true, 'a ROUTE is outdoors')
  -- the planes are derived from the grid, never a second stored copy that
  -- could drift out of step with it
  for i = 1, 12 do
    eq(mv.metatileCells[i], w:metatileAt((i - 1) % 4, math.floor((i - 1) / 4)),
      'plane cell ' .. i .. ' agrees with the per-cell reader')
  end
end)()

-- a warp replaces the map underneath, so the view must not be cached
;(function()
  local g = fixtureGame()
  local w = WorldAPI3.new(g, 'test')
  eq(w:mapView().id, 'TESTMAP', 'the first view names the first map')
  g.map = { id = 'OTHER', width = 1, height = 1, grid = { 99 },
    mapType = Game3.MAP_TYPE_INDOOR }
  local mv = w:mapView()
  eq(mv.id, 'OTHER', 'after a warp the view follows')
  eq(mv.width, 1, 'with the new dimensions')
  eq(mv.outdoor, false, 'and the new map type')
  eq(mv.metatileCells[1], 99, 'and the new cells')
end)()

-- activeBlockAt fails closed when the map moved under a stale caller
;(function()
  local g = fixtureGame()
  local w = WorldAPI3.new(g, 'test')
  eq(w:activeBlockAt('TESTMAP', 0, 0), 101, 'the active map answers')
  eq(select(2, w:activeBlockAt('SOMEWHERE_ELSE', 0, 0)), 'map is not active',
    'a stale map id fails closed rather than reading the wrong map')
end)()

-- the gaps are named, not silent, and answer the same shape as a failure
;(function()
  local g = fixtureGame()
  local w = WorldAPI3.new(g, 'test')
  check(type(WorldAPI3.UNIMPLEMENTED) == 'table',
    'the gaps are published, not discovered one warning at a time')
  local n = 0
  for name, reason in pairs(WorldAPI3.UNIMPLEMENTED) do
    n = n + 1
    check(type(reason) == 'string' and #reason > 0,
      name .. ' says why it is missing')
    local value, why = w[name](w)
    eq(value, nil, name .. ' answers nil')
    eq(why, reason, 'with that same reason as the second return')
  end
  check(n > 10, 'and there are a real number of them, honestly listed')
  -- the implemented ones are NOT in that table
  eq(WorldAPI3.UNIMPLEMENTED.mapView, nil, 'mapView is implemented')
  eq(WorldAPI3.UNIMPLEMENTED.elevationAt, nil, 'so is elevationAt')
end)()

-- the per-generation arm table, which is what stops the fall-through
;(function()
  local body = io.open('src/mods/Loader.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  check(text:find('GENERATION_HOMES', 1, true) ~= nil,
    'the world/battle arms come from a table, not a Gen 2 ternary')
  check(text:find('src.world.gen3.WorldAPI', 1, true) ~= nil,
    'and Gen 3 has a home in it')
  -- Ruby has no Gen 3 BattleAPI yet, and nil is the honest answer: falling
  -- through to Gen 1's would wrap Red's battle API around Game3
  check(text:find('%[3%] = { WorldAPI') ~= nil,
    'the Gen 3 row lists what exists and omits what does not')
end)()

-- ---------------------------------------------------- src.world.Map on Ruby
;(function()
  local Map = Gen3Compat.resolve('src.world.Map', 'test')
  check(Gen3Compat.serves('src.world.Map'), 'Gen3Compat serves it now')
  -- Ruby answers this from the GBA header's map type, where Red infers it
  -- from a tileset name
  eq(Map.isOutdoor({ mapType = Game3.MAP_TYPE_ROUTE }), true, 'a route is outside')
  eq(Map.isOutdoor({ mapType = Game3.MAP_TYPE_CITY }), true, 'so is a city')
  eq(Map.isOutdoor({ mapType = Game3.MAP_TYPE_INDOOR }), false,
    'and an indoor map is not')
  eq(Map.isOutdoor({ mapType = Game3.MAP_TYPE_SECRET_BASE }), false,
    'nor a secret base')
  eq(Map.isOutdoor({ mapType = Game3.MAP_TYPE_ROUTE, outdoor = false }), false,
    'an explicit flag wins, the way Gen 1 lets it')
  eq(Map.isOutdoor(nil), false, 'and a missing def is not outdoors')
  -- Map.new has no Gen 3 object to construct, so it is absent rather than
  -- returning something Gen 1 shaped
  eq(Map.new, nil, 'Map.new is not served')
  eq(Gen3Compat.memberStatus('src.world.Map', 'isOutdoor'), 'backed',
    'and coverage says which is which')
  eq(Gen3Compat.memberStatus('src.world.Map', 'new'), 'absent', 'both ways')
end)()


-- --------------------------------------------- Game.overworld on Ruby
--
-- Ruby has no OverworldController: the map, camera, NPCs and world draw are
-- fields and methods on the Game3 instance. src/core/Game3ModWorld.lua builds
-- the SHAPE a mod expects over those, so a renderer mod is drop-in rather than
-- needing a Ruby-specific route.
--
-- What keeps that from being the plausible-wrong-answer the facade exists to
-- stop is one rule: every field is a live read off the game, and anything Ruby
-- genuinely lacks stays absent. A different shape over real state is safe; a
-- real shape over invented state is the thing that burned us when the loader
-- handed Gen 3 mods Gold's modules.

-- a 4x3 fixture, planes disjoint the same way the WorldAPI one is
local function owGame()
  local g = Game3.new()
  g.phase = 'play'
  local grid = {}
  for i = 1, 12 do
    grid[i] = (100 + i) + (i % 2) * 1024 + (5 + i % 4) * 4096
  end
  g.map = { id = 'TESTMAP', width = 4, height = 3, grid = grid,
    border = { 468, 469, 476, 477 }, tileset = 'pair_a',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { pair_a = {
    behavior = { [101] = 0x10 }, layerType = { [101] = Game3.LAYER_COVERED },
    metatileCount = 1024 } } }
  g.playerX, g.playerY, g.facing = 2, 1, 'south'
  g.camX, g.camY = 8, 16
  g.npcByMap = {}
  return g
end

;(function()
  local g = owGame()
  local ow = g:modOverworld()
  check(ow ~= nil, 'a game standing in a map has an overworld view')
  eq(ow.isOverworld, true, 'flagged the way WorldAPI and mods test for')
  eq(ow.generation, 3, 'and says which generation it is')
  eq(ow.player.cellX, 2, 'the player cell x')
  eq(ow.player.cellY, 1, 'and y')
  eq(ow.player.facing, 'south', 'and facing')
  eq(ow.player.px, 32, 'pixels are derived at 16px a metatile, not stored')
  eq(ow.camera.x, 8, 'the camera x')
  eq(ow.camera.y, 16, 'and y')
  -- a game with no map is not a world, however live it otherwise looks
  -- The proxy OUTLIVES a map change on purpose: a mod that wrapped
  -- keypressed at load captured whatever this returned then, before any map
  -- existed. So the table persists and its fields answer nil instead --
  -- which says the same thing without the identity moving under a holder.
  local held = g:modOverworld()
  g.map = nil
  eq(g:modOverworld(), held, 'the overworld table survives losing the map')
  eq(held.map, nil, 'but reports no map')
  eq(held.player, nil, 'and no player')
  eq(held.isOverworld, nil,
    'and is not flagged as a world, which is what a reader tests')
end)()

-- THE TESTS THE MOD ITSELF RUNS. Gen3.isGen3 reads exactly these two numbers,
-- and the metatile path is chosen by `tileset.blocks` being absent -- a Gen 3
-- tileset has no Gen 1 block table, and supplying one would send the mod down
-- the wrong branch.
;(function()
  local ow = owGame():modOverworld()
  local ts = ow.map.tileset
  eq(ts.blockTiles, 2, 'a Gen 3 block is two 8px tiles on a side')
  eq(ts.blockCells, 1, 'and IS one collision cell, where Gen 1/2 holds four')
  check(tonumber(ts.blockTiles) == 2 and tonumber(ts.blockCells) == 1,
    'which is literally the test Gen3.isGen3 performs')
  eq(ts.blocks, nil,
    'and `blocks` is absent, so the mod takes the metatile path')
  eq(ow.map.tileAt, nil,
    'tileAt is absent for the same reason -- it is a Gen 1/2 question')
end)()

-- the map view a mesher walks
;(function()
  local ow = owGame():modOverworld()
  local m = ow.map
  eq(m.id, 'TESTMAP', 'the view names the map')
  eq(m.def.width, 4, 'def carries the width')
  eq(m.def.height, 3, 'and the height')
  eq(#m.def.collisionCells, 12, 'a collision plane, one per cell')
  eq(#m.def.elevationCells, 12, 'and an elevation plane -- the Y axis Gen 2 '
    .. 'records nowhere')
  eq(m.def.collisionCells[1], 1, 'plane values come off the grid word')
  eq(m.def.elevationCells[1], 6, 'and the two planes are separate fields')
  check(m.def.collisionCells[1] ~= m.def.elevationCells[1],
    'which this fixture can actually tell apart')
  eq(m.def.outdoor, true, 'a ROUTE is outdoors')

  eq(m:blockAt(0, 0), 101, 'blockAt is the metatile, masked out of the word')
  eq(m:blockAt(3, 2), 112, 'at the far corner too')
  -- collision 0 walks, 1..3 do not
  eq(m:isWalkableCell(0, 0), false, 'collision 1 is not walkable')
  eq(m:isWalkableCell(1, 0), true, 'collision 0 is')
  eq(m:elevationAt(0, 0), 6, 'and elevation reads its own bits')

  -- the two attribute planes the cartridge states outright
  local b, l = m:attributes(101)
  eq(b, 0x10, 'the behaviour byte comes from the tileset')
  eq(l, Game3.LAYER_COVERED, 'and the layer type beside it')
end)()

-- fieldmap.c GetBorderBlockAt: the ring outside the body repeats a 2x2 patch
-- by parity. Clamping instead gives every ring cell the patch's FIRST entry,
-- so three of every four come from the wrong quarter of the drawing -- the
-- mod's own notes call that out as a bug it hit elsewhere.
;(function()
  local m = owGame():modOverworld().map
  eq(m:blockAt(-1, -1), 468, 'the ring indexes the patch by parity')
  eq(m:blockAt(0, -1), 469, 'x parity picks the next quarter')
  eq(m:blockAt(-1, 0), 476, 'y parity steps a row')
  eq(m:blockAt(0, 0) == 468, false, 'and inside the body it is the real cell')
  check(m:blockAt(-1, -1) ~= m:blockAt(0, -1),
    'two adjacent ring cells differ -- a clamp would make them equal')
end)()

-- nothing is cached: a warp replaces the map and a step moves the player
;(function()
  local g = owGame()
  eq(g:modOverworld().map.id, 'TESTMAP', 'the first view names the first map')
  eq(g:modOverworld().player.cellX, 2, 'and the first position')
  g.playerX = 3
  eq(g:modOverworld().player.cellX, 3, 'a step is visible on the next read')
  g.map = { id = 'ELSEWHERE', width = 1, height = 1, grid = { 7 },
    tileset = 'pair_a', mapType = Game3.MAP_TYPE_INDOOR }
  local ow = g:modOverworld()
  eq(ow.map.id, 'ELSEWHERE', 'and a warp replaces the map')
  eq(ow.map.def.outdoor, false, 'with its own map type')
  eq(ow.map:blockAt(0, 0), 7, 'and its own cells')
end)()

-- `transitioning` and `inputLocked` are read off Game3:displayGateOK -- the
-- same test the zoom and tilt hotkeys gate on -- rather than a flag invented
-- for this view, so they cannot drift from what the engine calls free roam.
;(function()
  local g = owGame()
  eq(g:modOverworld().transitioning, false, 'free roam is not transitioning')
  eq(g:modOverworld().player.inputLocked, false, 'and input is not locked')
  g.field = { kind = 'menu' }
  eq(g:modOverworld().transitioning, true, 'a menu open counts as busy')
  eq(g:modOverworld().player.inputLocked, true, 'and locks steering')
  g.field = nil
  g.phase = 'boot'
  eq(g:modOverworld().transitioning, true, 'so does the boot cinema')
end)()

-- gen3WorldFor: the seam the mod tries before baking its own atlas. nil when
-- the art has not loaded, which the mod reads as 'the host does not publish
-- this' and falls back -- the right answer, since an atlas-less world record
-- would texture nothing. engineWorld() requires world.bottom to be truthy.
;(function()
  local g = owGame()
  -- pcall'd: dropping the atlas guard makes this THROW rather than return a
  -- bad record, and a throw here would abort the suite instead of failing one
  -- assertion -- which is how the mutation for it first went unreported
  local ok, world = pcall(g.gen3WorldFor, g, nil, g.map, nil)
  check(ok, 'asking with no atlas loaded does not throw')
  eq(world, nil, 'it declines instead -- the seam answers nil')
  -- with one, it hands over the atlas Ruby already built
  local fake = { getWidth = function() return 512 end,
                 getHeight = function() return 512 end }
  g.layersFor = function() return fake, fake end
  local world = g:gen3WorldFor(nil, g.map, nil)
  check(world ~= nil, 'with an atlas it publishes a world record')
  eq(world.generation, 3, 'tagged Gen 3')
  check(world.bottom ~= nil and world.bottom ~= false,
    'with a truthy bottom, which is what engineWorld() tests for')
  eq(world.cell, 16, 'a Gen 3 metatile is 16px')
  eq(world.width, 512, 'and the atlas dimensions come off the image')
  local b, l = world.attributes(101)
  eq(b, 0x10, 'attributes(id) answers the behaviour byte')
  eq(l, Game3.LAYER_COVERED, 'and the layer type')
  -- include/global.fieldmap.h: COVERED is bottom + middle BG, so its top
  -- half is BELOW the sprites; NORMAL and SPLIT put theirs on BG1, above. An
  -- earlier version of this test asserted the inverse, and pinned the bug
  -- that made every roof and treetop read as ground to the voxel mod.
  eq(world.topIsAbovePlayer(101), false,
    'LAYER_COVERED keeps its top half UNDER the player -- a fence, a path')
  eq(world.topIsAbovePlayer(102), true,
    'a NORMAL metatile draws its top half above the player -- a roof, a crown')
end)()

-- and the facade publishes it under both names mods use
;(function()
  local g = owGame()
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve('src.core.Game', 'test')
  check(Game.overworld ~= nil, 'Game.overworld resolves on Ruby now')
  eq(Game.overworld.map.id, 'TESTMAP', 'and it is the live map')
  check(Game.world ~= nil, 'Gen 2 spells it .world; both reach the same view')
  eq(Game.world.map.id, Game.overworld.map.id, 'and agree')
  eq(Gen3Compat.memberStatus('src.core.Game', 'overworld'), 'backed',
    'coverage says backed rather than absent now')
  -- the renderer object genuinely does not exist and stays absent: Ruby draws
  -- the world in Game3:drawWorldBody with no Renderer holding an override
  eq(Game.renderer, nil, 'renderer is still absent, not fabricated')
  eq(Gen3Compat.memberStatus('src.core.Game', 'renderer'), 'absent',
    'and coverage still says so')
end)()


-- ------------------------------ the seam is handed a VIEW, not the map
--
-- The caller of gen3WorldFor is a mod, and what a mod holds is the view from
-- modMapView -- which has no `grid`, because the grid is the engine's. The
-- first version did `map = map or self.map` and then tested `map.grid`, so it
-- answered nil for every map: the mod fell through to baking its own atlas,
-- found no map_tilesets entry for a Ruby tileset, and meshed nothing.
--
-- The symptom was two warnings in the MOD's log and silence in ours. Checking
-- our own fields one at a time could not have found it; running the mod's own
-- arm against the view did, first try.
;(function()
  local g = owGame()
  local fake = { getWidth = function() return 512 end,
                 getHeight = function() return 512 end }
  g.layersFor = function() return fake, fake end
  local view = g:modMapView(g.map)
  eq(view.grid, nil, "a map view carries no grid -- that is the engine's")

  local ok, world = pcall(g.gen3WorldFor, g, view.def, view, view.tileset)
  check(ok, 'handing the seam a view does not throw')
  check(world ~= nil,
    'and it builds a world record -- the seam accepts what a mod actually holds')
  check(world and world.bottom,
    'with a truthy bottom, which is what the mod tests before using the seam')

  -- the live map still works, and so does nil
  check(select(1, g:gen3WorldFor(nil, g.map, nil)) ~= nil,
    'the live map is still accepted')
  check(select(1, g:gen3WorldFor(nil, nil, nil)) ~= nil,
    'and nil falls back to the active map')
end)()

-- resolving a view goes by id, so a NEIGHBOUR's view resolves to that
-- neighbour rather than silently to the active map
;(function()
  local g = owGame()
  local other = { id = 'NEIGHBOUR', width = 1, height = 1, grid = { 42 },
    tileset = 'pair_a', mapType = Game3.MAP_TYPE_ROUTE }
  g.mapPlacements = function() return { { map = g.map, ox = 0, oy = 0 },
    { map = other, ox = 4, oy = 0 } } end
  eq(g:modResolveMap(g:modMapView(other)), other,
    "a neighbour's view resolves to that neighbour")
  eq(g:modResolveMap(g:modMapView(g.map)), g.map,
    'and the active map to itself')
  eq(g:modResolveMap(nil), g.map, 'nil means the active map')
  eq(g:modResolveMap({ id = 'NOWHERE' }), g.map,
    'an unknown id falls back to the active map rather than to nil')
end)()


-- ------------------------------ both call conventions through the facade
--
-- Gen 1's Game is a MODULE, so `Game.foo(x)` and `Game:foo(x)` are the same
-- call there and a mod may write either. DRAMATIC_SHAPE writes both in one
-- block: `local inner = Game.keypressed` then `function Game:keypressed(key)`.
--
-- Ruby's are instance methods needing the game as self, so a plain bind makes
-- the colon form pass self twice and land the real argument one slot along --
-- silently, because Lua does not mind an extra argument. That is how the
-- mod's hotkey wrapper received the GAME where it expected the key.
;(function()
  local g = Game3.new()
  g.party = {}
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve('src.core.Game', 'test')
  local dotted = Game.startMenuItems()
  local colon = Game:startMenuItems()
  check(type(dotted) == 'table' and #dotted > 0,
    'Game.foo() works -- the convention a Gen 1 mod writes')
  check(type(colon) == 'table' and #colon > 0,
    'and Game:foo() works too -- the one main.lua and a wrapper use')
  eq(#dotted, #colon, 'and they return the same thing')

  -- The case a plain bind really breaks, and which the two calls above do NOT
  -- reach: a mod READS the function out and calls it later with an explicit
  -- self, `inner(self, key)`. Bound, that becomes value(g, self, key) and the
  -- real argument lands one slot along -- silently.
  local seen = {}
  g.startMenuIndex = function(_, name) seen[#seen + 1] = tostring(name) end
  local inner = Game.startMenuIndex
  inner(Game, 'MODS')
  eq(seen[1], 'MODS',
    'a function read out and called with an explicit self still gets its '
    .. 'own argument in the right slot')
  inner('SAVE')
  eq(seen[2], 'SAVE', 'and the same function called without one does too')
end)()

-- the wrap shape verbatim: read the old function, replace it with a colon
-- definition, and confirm the replacement receives the KEY
;(function()
  local g = Game3.new()
  g.phase = 'play'
  Gen3Compat.bind(function() return g end)
  local Game = Gen3Compat.resolve('src.core.Game', 'test')
  local inner = Game.keypressed
  eq(type(inner), 'function', 'the original is readable through the facade')
  local seen = {}
  function Game:keypressed(key) seen[#seen + 1] = tostring(key) end
  check(rawget(g, 'keypressed') ~= nil,
    'the assignment lands on the live game, not on the proxy')
  g:keypressed('3')
  eq(seen[1], '3',
    'and the wrapper is handed the key, not the game -- which is the whole bug')
  eq(#seen, 1, 'exactly once')
end)()

-- ---------------------------------------- pipeline hotkeys reach Ruby
--
-- Mod pipelines claim their keys LAST, so one can never shadow an engine
-- display key -- Gen 1 orders it the same way. Before this, Ruby offered keys
-- to nothing at all: Game3:hotkey owns 3 for TILT and returns true, and the
-- options row a mod would otherwise use needs src.ui.OptionsMenu, which
-- Gen3Compat does not serve. There was no way to switch a pipeline on.
;(function()
  local Pipelines = require('src.render.Pipelines')
  local g = Game3.new()
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} } }
  -- an unclaimed key falls through to Input, which needs its bindings
  require('src.core.Input'):init()
  check(type(g.pipelineHotkey) == 'function', 'Ruby offers keys to pipelines')
  Pipelines.install({ render_pipelines = { ts = { id = 'ts', hotkey = '6',
    present = function() end, levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('ts', 0)
  eq(Pipelines.level('ts'), 0, 'the pipeline starts switched off')
  g:keypressed('6')
  eq(Pipelines.level('ts'), 1, 'and its declared hotkey cycles it on')
  -- an engine display key is NOT surrendered: 3 is Ruby's TILT
  Pipelines.install({ render_pipelines = { tilt = { id = 'tilt', hotkey = '3',
    present = function() end, levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('tilt', 0)
  g:keypressed('3')
  eq(Pipelines.level('tilt'), 0,
    'a pipeline cannot shadow an engine display key -- 3 stays TILT, and a '
    .. 'mod that wants it wraps keypressed instead')

  -- THE GATE. Zoom.gateOK refuses unless the overworld is what the player is
  -- looking at, so a mode cannot flip mid-warp or with a menu open. Ruby has
  -- no stack to read a top from; displayGateOK is its answer to the same
  -- question, and without it a press during a menu would still cycle.
  Pipelines.install({ render_pipelines = { ts2 = { id = 'ts2', hotkey = '7',
    present = function() end, levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('ts2', 0)
  g.field = { kind = 'menu' }
  eq(g:displayGateOK(), false, 'a menu open is not free roam')
  g:keypressed('7')
  eq(Pipelines.level('ts2'), 0, 'so the hotkey is refused while it is up')
  g.field = nil
  g:keypressed('7')
  eq(Pipelines.level('ts2'), 1, 'and works again once the menu closes')
end)()


-- ------------------------- the free-roam gate, as a MOD actually calls it
--
-- This is what made the voxel hotkey silently do nothing in a real session
-- while every test above passed. Three separate things had to be true and
-- none of them were:
--
--   1. The mod computes `top` ITSELF -- `local top = self.stack and
--      self.stack:top()` -- and Ruby had no stack, so top was nil and
--      Zoom.gateOK refused on its first line.
--   2. Its wrapper runs as a METHOD on the live Game3, so `self` is the raw
--      instance and the mod facade is not in the path. Publishing stack and
--      overworld through Gen3Compat alone reached nothing.
--   3. Zoom.gateOK tests `top ~= overworld` by IDENTITY, and modOverworld
--      built a fresh table per call -- so two equally live tables failed the
--      comparison every time.
;(function()
  local Pipelines = require('src.render.Pipelines')
  require('src.core.Input'):init()
  local g = Game3.new()
  g.phase = 'play'
  g:publishModWorld()

  -- a mod's entry chunk runs at load, BEFORE any map exists, and captures
  -- whatever these are then
  local capturedStack, capturedOw = g.stack, g.overworld
  check(capturedStack ~= nil, 'game.stack exists on the instance at load')
  check(capturedOw ~= nil, 'and so does game.overworld')
  eq(capturedStack.top(), nil, 'with no map, nothing is on top')

  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} } }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}

  eq(g.stack, capturedStack, 'the stack a mod captured survives a map load')
  eq(g.overworld, capturedOw, 'and so does the overworld it captured')
  eq(capturedOw.map and capturedOw.map.id, 'M',
    'and that captured proxy now reports the live map -- stable identity, '
    .. 'never a snapshot')
  eq(g.overworld, g.overworld, 'reading it twice gives the same table')

  -- the gate, computed exactly as the mod computes it
  Pipelines.install({ render_pipelines = { voxel = { id = 'voxel',
    hotkey = '3', drawWorld = function() end,
    levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('voxel', 0)
  local top = g.stack and g.stack:top()
  eq(top, g.overworld,
    'stack:top() IS the overworld in free roam -- Zoom.gateOK compares them '
    .. 'by identity, so two live-but-different tables would refuse')
  eq(Pipelines.canToggle('voxel', top, g.overworld), true,
    'so the gate opens and the hotkey can switch the mode on')

  -- and closes again when a screen owns the keyboard
  g.field = { kind = 'menu' }
  eq(g.stack:top(), nil, 'a menu open puts nothing on top')
  eq(Pipelines.canToggle('voxel', g.stack:top(), g.overworld), false,
    'and the gate refuses, which is what it is for')
  g.field = nil
  eq(Pipelines.canToggle('voxel', g.stack:top(), g.overworld), true,
    'free roam again')
end)()

-- the mod manager borrows game.stack while it is open, and gives it back
;(function()
  local g = Game3.new()
  g.phase = 'play'
  g:publishModWorld()
  local standing = g.stack
  g.modStatus = { available = { { id = 'x' } } }
  g:openModManager()
  check(g.stack ~= standing, 'the manager pushes a real StateStack')
  g:closeModManager()
  eq(g.stack, standing,
    'and closing gives the standing one back -- not nil, which would strand '
    .. 'a mod that captured it at boot')
end)()


-- ------------------------------------ and load() actually publishes them
--
-- Every test above calls publishModWorld by hand, so deleting the call from
-- Game3:load passed all of them clean -- the same draw-site gap that has bitten
-- this suite before. The only thing that catches it is running load().
;(function()
  local calls = 0
  local real = Game3.publishModWorld
  local g = Game3.new()
  g.publishModWorld = function(self) calls = calls + 1 return real(self) end
  local ok = pcall(function() g:load() end)
  check(ok, 'Game3:load runs headlessly')
  eq(calls, 1, 'and calls publishModWorld exactly once')
  check(g.stack ~= nil, 'so a loaded game has game.stack')
  check(g.overworld ~= nil, 'and game.overworld')
  check(g.save ~= nil and g.save.options ~= nil,
    'and game.save.options -- every engine path around a display hotkey ends '
    .. 'in syncOptions/tilt/writeOptions, and a mod delegating to those reads '
    .. 'it. Ruby only built it when the mod MANAGER opened, so the first '
    .. 'hotkey press of a session indexed nil and took the game down')

  -- the three lines a mod delegates to, run verbatim against a loaded game
  local Pipelines = require('src.render.Pipelines')
  Pipelines.install({ render_pipelines = { v = { id = 'v', hotkey = '3',
    drawWorld = function() end, levels = { 'OFF', 'ON' } } } })
  local ran = pcall(function()
    Pipelines.setLevel('v', 1)
    Pipelines.syncOptions(g.save.options)
    require('src.render.Tilt').setLevel(g.save.options.tilt or 0)
    g:writeOptions()
  end)
  check(ran, "and the engine's own post-hotkey block runs without throwing")
  check(type(g.stack.top) == 'function', 'with a stack a mod can read a top from')
  -- and it happens BEFORE the mods load, since a mod entry chunk may capture
  -- both as it runs
  local body = io.open('src/core/Game3.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  local atPublish = text:find('self:publishModWorld()', 1, true)
  local atMods = text:find('mods:load(self.data)', 1, true)
  check(atPublish ~= nil, 'load publishes them')
  check(atMods ~= nil and atPublish < atMods,
    'and does it before mods:load, so an entry chunk can capture them')
end)()


-- --------------------------------------------------- src.render.GBCFX
--
-- The Game Boy Colour filter has no meaning on a GBA cartridge. Served
-- anyway, because a require that THROWS is the worst of the three possible
-- answers -- and it threw, inside the mod's hotkey handler, taking the game
-- down on the press that was finally about to work.
--
-- DRAMATIC_SHAPE calls exactly one function on it, and not to USE the effect:
-- key 3 used to turn TILT on and sits beside the key that turned GBC FX on,
-- so the mod clears both on every press to leave a player who had one running
-- a way back. On Ruby that is already true, so accepting the call and doing
-- nothing is the honest implementation rather than a cop-out.
;(function()
  check(Gen3Compat.serves('src.render.GBCFX'),
    'the name resolves instead of throwing')
  local F = Gen3Compat.resolve('src.render.GBCFX', 'test')
  local ok = pcall(F.setLevel, 0)
  check(ok, 'setLevel(0) -- the one call the mod makes -- is accepted')
  eq(F.active(), false, 'and nothing is ever running to report')
  eq(F.isSupported(), false, 'the filter is not supported on a GBA cartridge')
  eq(F.levelLabel(0), 'OFF', 'and its label says so')
  -- present must hand the canvas BACK: returning nil here blanks the screen,
  -- since the caller composites whatever it gets
  local canvas = { marker = true }
  eq(F.present(canvas), canvas, 'present passes its canvas through unchanged')
  eq(Gen3Compat.memberStatus('src.render.GBCFX', 'setLevel'), 'warned',
    'coverage calls it warned, not backed: a mod that WANTED the effect gets '
    .. 'nothing, and should be able to see that')
end)()

-- the whole sequence cycleVoxel runs, verbatim, against a loaded game --
-- which is what four separate crashes in a row were each one line of
;(function()
  local Pipelines = require('src.render.Pipelines')
  require('src.core.Input'):init()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} } }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  Gen3Compat.bind(function() return g end)
  Pipelines.install({ render_pipelines = { voxel = { id = 'voxel',
    hotkey = '3', drawWorld = function() end,
    levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('voxel', 0)

  local ran, err = pcall(function()
    local top = g.stack and g.stack:top()
    if not Pipelines.canToggle('voxel', top, g.overworld) then
      error('the free-roam gate refused', 0)
    end
    Pipelines.setLevel('voxel', 1)
    Pipelines.syncOptions(g.save.options)
    g.save.options.tilt = 0
    g.save.options.gbcfx = 0
    Gen3Compat.resolve('src.render.GBCFX', 'test').setLevel(0)
    require('src.render.Tilt').setLevel(g.save.options.tilt or 0)
    g:writeOptions()
  end)
  check(ran, "the mod's whole cycleVoxel sequence runs: " .. tostring(err))
  eq(Pipelines.level('voxel'), 1, 'and the mode ends up switched on')
  eq(Pipelines.worldPipeline(), 'voxel', 'owning the world pass')
end)()


-- ------------------------------ the per-frame tick a pipeline needs
--
-- A render pipeline is not only a draw. The voxel mod queues a map's mesh on
-- the frame it is first asked for and advances that queue in `update` --
-- which Gen 1 and Gen 2 both call every frame and Ruby did not. The symptom
-- was one line, once: 'no mesh for g0_9 yet (queued) -- flat for now'. Nothing
-- further was ever logged, because the mod prints that once per map id, so
-- the world just stayed flat with no error anywhere.
--
-- Headless tests could not have found this: nothing here ran a frame loop.
;(function()
  local Pipelines = require('src.render.Pipelines')
  require('src.core.Input'):init()
  local g = Game3.new()
  pcall(function() g:load() end)
  local ticks, sawLevel = 0, nil
  Pipelines.install({ render_pipelines = { v = { id = 'v', hotkey = '3',
    drawWorld = function() end,
    update = function(dt, level) ticks = ticks + 1 sawLevel = level end,
    levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('v', 1)
  for _ = 1, 3 do g:update(1 / 60) end
  eq(ticks, 3, 'a registered pipeline is ticked once per frame')
  eq(sawLevel, 1, 'and told which rung it is on')

  -- real time, beside audio and tilt: what a pipeline does with the tick is
  -- build work, not gameplay, so GAME SPEED must not stretch or skip it
  local body = io.open('src/core/Game3.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  local atTilt = text:find('require("src.render.Tilt").update(dt)', 1, true)
  local atPipes = text:find('require("src.render.Pipelines").update(dt)', 1, true)
  local atSpeed = text:find('local speed = self:logicSpeed()', 1, true)
  check(atPipes ~= nil, 'Ruby ticks the pipeline registry')
  check(atTilt and atPipes > atTilt, 'beside the other real-time updates')
  check(atSpeed and atPipes < atSpeed,
    'and before the game-speed scaling, so a sped-up game does not starve '
    .. 'or flood a mesher')
end)()

-- a pipeline whose update throws must not take the frame down
;(function()
  local Pipelines = require('src.render.Pipelines')
  local g = Game3.new()
  pcall(function() g:load() end)
  Pipelines.install({ render_pipelines = { bad = { id = 'bad',
    drawWorld = function() end,
    update = function() error('mod blew up in update') end,
    levels = { 'OFF', 'ON' } } } })
  Pipelines.setLevel('bad', 1)
  local ok = pcall(function() g:update(1 / 60) end)
  check(ok, 'a throwing pipeline update does not take the frame down')
end)()


-- ------------------------------- what a pipeline is handed to draw with
--
-- `ctx.state` is Gen 1's OverworldController, and a mod reaches THROUGH it
-- for the things an overworld has: VoxelScene.render's very first line is
-- `local cam = state.camera`. Handing over the raw Game3 put a GAME in that
-- slot -- camX and camY, no `.camera` -- and the pipeline died on its first
-- draw with 'attempt to index local cam (a nil value)', which the engine
-- reported as the mod failing rather than as the host handing it the wrong
-- shape.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 2, height = 2, grid = { 1, 2, 3, 4 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.camX, g.camY = 24, 48

  local ctx = g:worldPipelineContext(1, 'voxel')
  eq(ctx.state, g:modOverworld(),
    'ctx.state is the overworld view, not the game')
  check(ctx.state.camera ~= nil, 'so it has a .camera, which a mod reads')
  eq(ctx.state.camera.x, 24, 'carrying the live camera x')
  eq(ctx.state.camera.y, 48, 'and y')
  check(ctx.state.map ~= nil, 'and a .map')
  eq(ctx.state.map.id, 'M', 'which is the live one')
  -- ctx.cam stays too: Gen 1 publishes both spellings and mods read both
  eq(ctx.cam.x, 24, 'ctx.cam is still there beside it')

  -- a tileset with no recorded count reports the ATLAS size, not zero: a mod
  -- printing '0 metatiles' reads as an empty tileset rather than as a field
  -- this engine does not store
  local ts = g:modMapView(g.map).tileset
  eq(ts.metatileCount, 1024,
    'a 32x32 atlas is 1024 metatiles -- 512 primary plus 512 secondary')
  g.data.tilesets.atlasRows = 16
  eq(g:modMapView(g.map).tileset.metatileCount, 512,
    'and it follows the pack rather than being hard-coded')
end)()


-- ------------------------------------------------------------- the cast
--
-- Gen 1 renderers walk `state.entities` and `state.ghosts` calling
-- `entity:pose()`, which hands back a SPRITE OBJECT plus position, facing,
-- phase and flip, and the object answers `:resolveImage()` and carries a
-- `.def` describing its sheet. Ruby has none of that -- plain NPC records, and
-- drawing that resolves a sheet and a quad at paint time -- so these lists
-- were empty for a while and the world came out unpopulated.
--
-- actorView builds the object over Ruby's real data now: data.sprites.byId
-- keyed by the NPC's graphicsId.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 4, height = 4,
    grid = { 1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = { behavior = {}, layerType = {} } },
    atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = { [0] = { id = 0, path = 'ow_0.png',
    width = 16, height = 32, frameCount = 9 } } }
  g.playerX, g.playerY, g.facing = 1, 1, 'east'
  g.npcByMap = { M = { { x = 2, y = 2, facing = 'west', graphicsId = 0 } } }
  g.playerGraphicsId = function() return 0 end

  local ow = g:modOverworld()
  eq(#ow.npcs, 1, 'the NPC on this map is in the cast')
  eq(#ow.entities, 2, 'and entities carries it plus the player')

  -- THE PLAYER IS ONE OF THEM, and by IDENTITY. Gen 1 marks the player in
  -- entities through state.player so a renderer can leave the card out in
  -- first person; two equal-but-different tables make it draw them twice.
  eq(ow.player, ow.entities[1],
    'state.player IS the entry in entities, not a copy of it')

  -- the pose contract, verbatim
  local sprite, px, py, facing, phase, flip = ow.player:pose()
  check(sprite ~= nil, 'pose returns a sprite object')
  eq(px, 16, 'and the pixel x, derived at 16px a cell')
  eq(py, 16, 'and y')
  eq(facing, 'east', 'and the facing')
  eq(phase, 0, 'phase 0 -- see walker below')
  eq(flip, false, 'and no stride mirror')
  eq(type(sprite.resolveImage), 'function', 'the sprite resolves its image')

  -- the def the consumer reads
  local def = sprite.def
  eq(def.image, 'ow_0.png', 'the sheet path comes off the sprite record')
  eq(def.frameWidth, 16, 'the frame width')
  eq(def.frameHeight, 32, 'and height')
  eq(def.frames, 9, 'and how many frames the sheet holds')
  eq(def.trueColor, true,
    'flagged true-colour: Ruby overworld art is GBA and must not be run '
    .. 'through a palette pass')
  eq(def.big, true, 'a 32px sprite is taller than its cell')

  -- WALKER IS FALSE, and it is the one deliberate loss. The consumer picks a
  -- sheet row from Gen 1's tables: STAND {down=0,up=1,left=2,right=2} and
  -- WALK {down=3,up=4,left=5,right=5}. Ruby's standing rows are IDENTICAL, so
  -- with walker false every direction and its mirror is exactly right. Its
  -- walking rows are not -- south [3,0,4,0], north [5,1,6,1], west [7,2,8,2] --
  -- so Gen 1's single WALK row lands on south's second step for north and on
  -- north's first for west. A correct still beats a wrong stride.
  eq(def.walker, false, 'walker is declined on purpose')
  local SR = require('src.render.SpriteRenderer')
  eq(SR.STAND.down, 0, "Gen 1's standing rows...")
  eq(SR.STAND.up, 1, '...')
  eq(SR.STAND.left, 2, '...')
  eq(SR.STAND.right, 2, '...are south 0, north 1, west 2, east 2 mirrored')
  check(SR.WALK.up ~= SR.STAND.up,
    'while its WALK rows are a different set, which is why they are declined')

  -- an actor is its own npc, so a consumer reaching either way lands here
  eq(ow.npcs[1].npc, ow.npcs[1], 'an actor is its own npc')
  eq(select(4, ow.npcs[1]:pose()), 'west', 'and poses with its own facing')
end)()

-- IDENTITY WITHIN A STATE. The proxy rebuilds on demand so a reader always
-- sees the live game -- but rebuilding on every READ gave two fields of one
-- view from two different builds, and that is what made player ~= entities[1]
-- the first time. The build is memoized against a signature of what it reads.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 2, height = 2, grid = { 1, 1, 1, 1 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = { [0] = { id = 0, path = 'p.png', width = 16,
    height = 32, frameCount = 9 } } }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  local ow = g:modOverworld()

  eq(ow.player, ow.player, 'two reads of one field agree')
  eq(ow.entities, ow.entities, 'and of another')
  eq(ow.player, ow.entities[1], 'and the two fields agree with each other')

  -- a step rebuilds: still live, just not rebuilt per read
  local before = ow.player
  g.playerX = 1
  check(ow.player ~= before, 'a step produces a new set')
  eq(ow.player.cellX, 1, 'reporting the new cell')
  eq(ow.player, ow.entities[1], 'and the two still agree afterwards')
end)()


-- ------------------------------------ TileRenderer.gen3SheetsFor
--
-- The name a renderer mod reaches for to get a map's art. What it wants back
-- is one method -- `tiles:bakeLayer(layer, plot)`, plot(x, y, r, g, b) per
-- pixel in metatile-sheet coordinates with 0..255 colour -- and it re-lays
-- those pixels into whatever layout it works in.
--
-- The engine this contract comes from answers it by compositing a tileset
-- PAIR from raw cartridge records every time a sheet is wanted. Ruby
-- composites once, at import, into pair_N_bottom.png / pair_N_top.png on a
-- 32x32 grid of 16px metatiles -- which is the same grid. So this reads the
-- atlas rather than shipping a second raw copy of data we already process.
;(function()
  local TileRenderer = require('src.render.TileRenderer')
  check(type(TileRenderer.gen3SheetsFor) == 'function',
    'the contract name is published on TileRenderer, where a mod looks')
  eq(TileRenderer.gen3SheetsFor({ id = 'x', blockTiles = 4 }, {}), nil,
    'a Gen 1/2 tileset gets nil, so those engines are untouched')
  eq(TileRenderer.gen3SheetsFor({ id = 'nope', blockTiles = 2 }, {}), nil,
    'and an unknown tileset declines rather than throwing')
end)()

-- the baking itself, against a stand-in atlas: PNG decoding needs LOVE, but
-- the layer choice, the colour units, the alpha skip and the frame switch are
-- all logic and all testable here
;(function()
  local Gen3Sheets = require('src.render.Gen3Sheets')
  Gen3Sheets.invalidate()

  -- ONE METATILE, because that is the unit bakeLayer walks in -- it restates
  -- each metatile's position in the consumer's 16-wide frame, so a fixture
  -- smaller than 16x16 has nothing to walk.
  --
  -- Pixel (0,0) carries the colour; (1,0) is transparent, to prove the skip.
  local function fakeImage(pixels)
    return {
      getDimensions = function() return 16, 16 end,
      getPixel = function(_, x, y)
        local px = (y == 0) and pixels[x + 1] or nil
        if not px then return 0, 0, 0, 0 end
        return px[1], px[2], px[3], px[4]
      end,
    }
  end
  local made = {
    ['b.png'] = fakeImage({ { 1, 0, 0, 1 }, { 0, 0, 0, 0 } }),
    ['t.png'] = fakeImage({ { 0, 0, 1, 1 }, { 0, 0, 0, 0 } }),
    ['b2.png'] = fakeImage({ { 0, 1, 0, 1 }, { 0, 0, 0, 0 } }),
  }
  local realImage, realFs = love.image, love.filesystem
  love.image = { newImageData = function(path) return made[path] end }
  love.filesystem = { getInfo = function(path)
    return made[path] and { type = 'file' } or nil
  end }

  local data = { tilesets = { atlasCols = 32, atlasRows = 32, byId = {
    pair_0 = { id = 'pair_0', bottom = 'b.png', top = 't.png',
      behavior = { [7] = 0x10 }, layerType = { [7] = 1 },
      anim = { frames = 8, layers = { { bottom = 'b.png', top = 't.png' },
        { bottom = 'b2.png', top = 't.png' } } } } } } }

  local record = Gen3Sheets.forTileset({ id = 'pair_0', blockTiles = 2 }, data)
  check(record ~= nil, 'a Gen 3 tileset bakes')
  eq(record.metatiles, 1024, '32x32 metatiles')
  -- the CONTRACT's dimensions: 1024 metatiles at 16 across is 16x64 cells
  eq(record.width, 256, 'the sheet is published 16 metatiles wide')
  eq(record.height, 1024, 'and as tall as that takes')
  local tiles = record.tiles
  check(tiles ~= nil, 'with a tiles object -- the only field the mod reads')

  local cols, rows, w, h = tiles:sheetLayout()
  eq(cols, 16, 'sheetLayout reports the contract width')
  eq(rows, 64, 'and the rows that width implies')
  eq(w, 256, 'and the pixel size that matches')
  eq(h, 1024, 'both ways')
  eq(tiles:metatileCount(), 1024, 'metatileCount agrees')

  -- the attributes the cartridge states outright
  local b, l = tiles:attributes(7)
  eq(b, 0x10, 'attributes reads the behaviour byte from the pack')
  eq(l, 1, 'and the layer type')
  eq(tiles:topIsAbovePlayer(7), false,
    'LAYER_COVERED keeps its top under the player (global.fieldmap.h)')
  eq(tiles:topIsAbovePlayer(8), true, 'and NORMAL puts its top above')

  -- LAYER 1 IS THE BOTTOM ATLAS, 2 IS THE TOP. Getting this backwards paints
  -- roofs on the ground and grass over the player.
  local seen = {}
  tiles:bakeLayer(1, function(x, y, r, g, bb)
    seen[#seen + 1] = ('%d,%d=%d/%d/%d'):format(x, y, r, g, bb)
  end)
  eq(#seen, 1, 'a fully transparent pixel is SKIPPED, not plotted black -- a '
    .. 'caller compositing both layers would otherwise have the second erase '
    .. 'the first')
  eq(seen[1], '0,0=255/0/0',
    'layer 1 is the bottom atlas, and colour arrives in 0..255')

  seen = {}
  tiles:bakeLayer(2, function(x, y, r, g, bb)
    seen[#seen + 1] = ('%d,%d=%d/%d/%d'):format(x, y, r, g, bb)
  end)
  eq(seen[1], '0,0=0/0/255', 'and layer 2 is the top atlas')

  -- the animation frames the importer already wrote out
  eq(tiles:animFrameCount(), 8, 'eight frames are recorded for this pair')
  tiles:setAnimFrame(1)
  seen = {}
  tiles:bakeLayer(1, function(x, y, r, g, bb)
    seen[#seen + 1] = ('%d/%d/%d'):format(r, g, bb)
  end)
  eq(seen[1], '0/255/0', 'setAnimFrame reaches the per-frame atlas on disk')
  tiles:setAnimFrame(0)
  seen = {}
  tiles:bakeLayer(1, function(x, y, r, g, bb)
    seen[#seen + 1] = ('%d/%d/%d'):format(r, g, bb)
  end)
  eq(seen[1], '255/0/0', 'and frame 0 is the static sheet again')

  -- animatedMetatiles is EMPTY on purpose: Ruby records that a pair animates
  -- but not which metatiles do, and a guess would send a caller re-baking the
  -- wrong hundred cells
  eq(#tiles:animatedMetatiles(), 0,
    'no guess is made about which metatiles move')

  -- THE GUARD, with the tileset actually present. Asking with blockTiles 4 --
  -- a Gen 1/2 block, four 8px tiles on a side -- must decline even though the
  -- record exists and would bake fine, because those atlases are not laid out
  -- as 16px metatiles and a caller would read them as if they were.
  Gen3Sheets.invalidate()
  eq(Gen3Sheets.forTileset({ id = 'pair_0', blockTiles = 4 }, data), nil,
    'a Gen 1/2 tileset is declined even when its record is right there')
  Gen3Sheets.invalidate()
  check(Gen3Sheets.forTileset({ id = 'pair_0', blockTiles = 2 }, data) ~= nil,
    'while the same record at blockTiles 2 bakes')

  love.image, love.filesystem = realImage, realFs
  Gen3Sheets.invalidate()
end)()


-- --------------------------- every field a drawWorld is handed, at once
--
-- Four separate crashes were each one missing ctx field, found one run at a
-- time: state (no .camera), then drawFx. Rather than wait for a fifth, this
-- is the whole set a real renderer's drawWorld reads -- DRAMATIC_SHAPE's
-- touches exactly six -- asserted together.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 2, height = 2, grid = { 1, 2, 3, 4 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.playerX, g.playerY, g.facing = 1, 1, 'south'
  g.npcByMap = {}
  g.camX, g.camY = 16, 32
  local ctx = g:worldPipelineContext(2, 'voxel')

  -- the six, by name
  eq(ctx.scale, 2, 'ctx.scale')
  -- vw/vh and width/height are DIFFERENT sizes and must not be collapsed;
  -- see the block below for what collapsing them did on a phone
  eq(ctx.vw, 240, 'ctx.vw is the world view in world pixels')
  eq(ctx.vh, 160, 'ctx.vh likewise')
  check(ctx.state ~= nil, 'ctx.state')
  check(ctx.state.camera ~= nil, 'which carries a camera')
  check(ctx.state.map ~= nil, 'and a map')
  eq(type(ctx.paletteFor), 'function', 'ctx.paletteFor is callable')
  eq(type(ctx.drawFx), 'function', 'and so is ctx.drawFx')

  -- callable WITHOUT throwing is the actual contract: a mod calls both
  -- unconditionally, and a nil there took the pipeline down
  check(pcall(ctx.paletteFor, ctx.state.map), 'paletteFor survives a call')
  check(pcall(ctx.drawFx, function(x, y) return x, y end, 2),
    'and drawFx survives the two-argument call the mod makes')
  eq(ctx.paletteFor(), nil,
    'paletteFor answers nil -- Ruby art is true-colour and never re-mapped')

  -- every one of the six present in a single sweep, so dropping any is a
  -- named failure rather than next run's crash
  for _, key in ipairs({ 'scale', 'vw', 'vh', 'state', 'paletteFor',
      'drawFx' }) do
    check(ctx[key] ~= nil, 'ctx.' .. key .. ' is present')
  end
end)()


-- --------------------------- every map method a renderer calls, at once
--
-- Same lesson as the ctx fields, learned again: the mod calls NINE methods on
-- a map and I had published two, so each run found the next missing one and
-- reported it as the mod failing. Enumerated from the mod this time.
--
-- Every answer comes from Game3's own readers -- the behaviour byte, the
-- collision bits, the warp list -- so the renderer gets the same answer the
-- game does rather than a second opinion that can drift.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  -- cell 0 tall grass, 1 deep water, 2 plain with a warp on it
  g.map = { id = 'M', width = 3, height = 1, grid = { 10, 11, 12 },
    tileset = 't', border = { 1, 2, 3, 4 }, mapType = Game3.MAP_TYPE_ROUTE,
    warps = { { x = 2, y = 0, dest = 'X' } } }
  g.data.tilesets = { byId = { t = { behavior = {
    [10] = Game3.MB_TALL_GRASS, [11] = Game3.MB_DEEP_WATER, [12] = 0 },
    layerType = {} } }, atlasCols = 32, atlasRows = 32 }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  local m = g:modOverworld().map

  -- all nine present in one sweep, so dropping any is a named failure
  for _, name in ipairs({ 'inBounds', 'isWalkableCell', 'isWaterCell',
      'cellTile', 'warpAtCell', 'isGrassCell', 'blockAt', 'isWarpTileCell',
      'behaviorAt' }) do
    eq(type(m[name]), 'function', 'map:' .. name .. ' is published')
  end
  eq(m.tileAt, nil,
    'tileAt stays absent -- it is a Gen 1/2 question and the mod guards on '
    .. 'tileset.blocks before ever asking it')

  -- and each answers correctly, not merely callably
  eq(m:inBounds(0, 0), true, 'a cell inside the body is in bounds')
  eq(m:inBounds(3, 0), false, 'and one past the right edge is not')
  eq(m:inBounds(-1, 0), false, 'nor one before the left')
  eq(m:inBounds(nil, 0), false, 'and a non-number is refused, not indexed')

  eq(m:behaviorAt(0, 0), Game3.MB_TALL_GRASS, 'the behaviour byte reads')
  eq(m:isGrassCell(0, 0), true, 'tall grass is grass')
  eq(m:isGrassCell(1, 0), false, 'water is not')
  eq(m:isWaterCell(1, 0), true, 'deep water is surfable, so it is water')
  eq(m:isWaterCell(0, 0), false, 'and grass is not')

  -- cellTile answers the BEHAVIOUR BYTE of a walkable cell (0xFF if blocked),
  -- which is what Emerald's Map:cellTile answers on a Gen 3 map and what every
  -- call site in the voxel mod compares against. An earlier version of this
  -- test pinned it to the metatile id -- a different number that matched
  -- none of doorTiles, the hop-lip rules or the collision-class shapes.
  eq(m:cellTile(0, 0), Game3.MB_TALL_GRASS,
    'cellTile is the behaviour byte of a walkable cell, not the metatile id')
  check(m:cellTile(0, 0) ~= m:blockAt(0, 0),
    'and this fixture can tell the two apart')

  eq(m:isWarpTileCell(2, 0), true, 'the warp cell is a warp')
  eq(m:isWarpTileCell(0, 0), false, 'and an ordinary cell is not')
  eq((m:warpAtCell(2, 0) or {}).dest, 'X', 'with the warp record behind it')
  eq(m:warpAtCell(0, 0), nil, 'and nil where there is none')
end)()


-- ------------------------- the cartridge's own names for a tileset pair
--
-- A renderer mod carries per-tileset shape profiles -- tree hulls, roof
-- massing, counter pins -- keyed by the cartridge's symbol names. Ruby
-- identified a pair only by an ordinal (`pair_0`), so every lookup missed and
-- every cell fell to the profile of last resort, which is a full-height wall.
-- On screen that turned Littleroot's border trees into a comb of black
-- monoliths around the map.
;(function()
  local X = require('src.import.RomExtractorGen3')
  local n = 0
  for _ in pairs(X.TILESET_NAMES or {}) do n = n + 1 end
  eq(n, 58, 'all 58 tileset headers, read out of pokeruby rather than typed')
  eq(X.tilesetName(0x286CF4), 'gTileset_General',
    'the address in the decomp comment resolves to its symbol')
  eq(X.tilesetName(0x28721C), 'gTileset_SecretBase', 'and so does a later one')
  eq(X.tilesetName(0x123456), nil,
    'an address that is not a header answers nil -- a missed profile beats a '
    .. 'wrong one')
  eq(X.tilesetName(nil), nil, 'and nil in, nil out')

  -- THE RECORD THE PACK SHIPS. Tested through the builder rather than by
  -- constructing a pack by hand, because that is exactly what let deleting
  -- these two fields pass every other test in this suite.
  local rec = X.tilesetRecord('pair_0', { bottom = 'b.png', behavior = {} },
    { primaryOff = 0x286CF4, secondaryOff = 0x286D0C })
  eq(rec.id, 'pair_0', 'the record keeps its ordinal id')
  eq(rec.primaryKey, 'gTileset_General',
    'and gains the cartridge name for its primary half')
  eq(rec.secondaryKey, 'gTileset_Petalburg', 'and for its secondary')
  eq(rec.primaryOff, 0x286CF4, 'the offsets ride along for anyone who wants them')
  eq(rec.bottom, 'b.png', 'without disturbing what was already there')
  local bare = X.tilesetRecord('pair_9', {}, { primaryOff = 0x111111 })
  eq(bare.primaryKey, nil,
    'an offset that is not a header names nothing rather than guessing')
end)()

-- every pair the cartridge actually uses must resolve, or the profiles only
-- half apply and the seams between named and unnamed maps look wrong
do
  local rf = io.open('misc/Pokemon - Ruby Version (USA).gba', 'rb')
  if rf then
    local rom = rf:read('*a')
    rf:close()
    local X = require('src.import.RomExtractorGen3')
    local hoenn = X.decodeHoenn(rom)
    local total, named = 0, 0
    local general
    for _, pair in pairs((hoenn or {}).pairs or {}) do
      total = total + 1
      if X.tilesetName(pair.primaryOff) then named = named + 1 end
      if pair.id == 'pair_0' then general = pair end
    end
    check(total > 40, 'Hoenn uses a real number of tileset pairs')
    eq(named, total, 'and EVERY one of them names its primary half')
    check(general ~= nil, 'pair_0 is there')
    eq(X.tilesetName(general.primaryOff), 'gTileset_General',
      'and its primary is the shared outdoor half every exterior uses')
    eq(X.tilesetName(general.secondaryOff), 'gTileset_Petalburg',
      'with Petalburg as its secondary')
  end
end

-- and the names reach the mod
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = { primaryKey = 'gTileset_General',
    secondaryKey = 'gTileset_Petalburg',
    behavior = { [0] = 0, [511] = 0, [900] = 0 } } },
    atlasCols = 32, atlasRows = 32 }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  local ts = g:modMapView(g.map).tileset
  eq(ts.primaryKey, 'gTileset_General',
    'the view hands over the name, not the ordinal')
  eq(ts.secondaryKey, 'gTileset_Petalburg', 'for both halves')
  eq(ts.primary, ts.primaryKey, 'under both spellings a mod might use')
  eq(ts.secondary, ts.secondaryKey, 'both ways')

  -- metatileCount is how many are DEFINED, not the atlas grid size. The grid
  -- is always 1024 because that is how the importer lays a pair out; a caller
  -- sizes shape tables from this, and for an indoor pair -- whose secondary
  -- defines a handful -- 1024 is wildly wrong.
  eq(ts.metatileCount, 901,
    'the highest behaviour id the importer wrote, plus one')
  g.data.tilesets.byId.t.behavior = nil
  eq(g:modMapView(g.map).tileset.metatileCount, 1024,
    'with no behaviour table it falls back to the atlas size rather than zero')
end)()

-- a pair the importer could not name falls back to the id, which is a missed
-- profile rather than a wrong one
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 'pair_9',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { pair_9 = {} }, atlasCols = 32, atlasRows = 32 }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  local ts = g:modMapView(g.map).tileset
  eq(ts.primaryKey, 'pair_9', 'an unnamed pair falls back to its id')
  eq(ts.secondaryKey, nil, 'and claims no secondary it cannot name')
end)()

-- the cache has to be rebuilt to carry the names
;(function()
  local C = require('src.import.CacheContract')
  local marker = C.formatFor('ruby')
  local n = tonumber(marker:match('rom%-cache%-v10%-ruby(%d+):'))
  check((n or 0) >= 100,
    'the ruby marker is at or past the build that added the tileset names')
  local wanted = false
  for _, f in ipairs(C.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
    if f == 'data/generated/tilesets.lua' then wanted = true end
  end
  check(wanted,
    'and the pack carrying them is required, so a v99 cache cannot validate')
end)()


-- ------------------------------ a mod's rows on Ruby's OPTION screen
--
-- A render pipeline is a display mode like TILT, so its row belongs BESIDE
-- it rather than after CANCEL -- Gen 1 splices at the same anchor. Until this,
-- Ruby's option screen was a fixed list and a mod's settings were reachable
-- only by number key, unlabelled.
;(function()
  local Pipelines = require('src.render.Pipelines')
  local Input = require('src.core.Input')
  Input:init()
  local g = Game3.new()
  pcall(function() g:load() end)

  Pipelines.install({ render_pipelines = {} })
  local vanilla = #g:optionMenuSpec()
  check(vanilla >= 9, 'the cartridge rows are there to begin with')
  eq(g:optionMenuSpec()[vanilla][3], 'cancel', 'and CANCEL is last')

  Pipelines.install({ render_pipelines = {
    voxel = { id = 'voxel', label = 'VOXEL', hotkey = '3',
      drawWorld = function() end, levels = { 'OFF', '15', '35' } } } })
  Pipelines.setLevel('voxel', 0)
  local spec = g:optionMenuSpec()
  eq(#spec, vanilla + 1, 'a registered pipeline adds exactly one row')
  eq(spec[#spec][3], 'cancel', 'and CANCEL is still last')

  local at, tiltAt
  for i, row in ipairs(spec) do
    if row[3] == 'extra:pipeline:voxel' then at = i end
    if row[3] == 'tilt' then tiltAt = i end
  end
  check(at ~= nil, 'the pipeline row is in the list')
  eq(spec[at][1], 'VOXEL', 'under the label the mod gave it')
  eq(spec[at][2], 'OFF', 'showing its current rung')
  check(tiltAt and at > tiltAt,
    'placed after TILT -- a display mode belongs with the display modes')

  -- stepping it: the row carries its own stepper, so the dispatch never has
  -- to learn a mod's row names
  local function press(key, cursor)
    g.field = { kind = 'option', cursor = cursor }
    local old = Input.wasPressed
    Input.wasPressed = function(_, k) return k == key end
    g:stepOptionMenu(g.field, function() end)
    Input.wasPressed = old
  end
  press('right', at - 1)
  eq(Pipelines.level('voxel'), 1, 'RIGHT advances the rung')
  eq(g:optionMenuSpec()[at][2], '15', 'and the row label follows the value')
  press('right', at - 1)
  eq(Pipelines.level('voxel'), 2, 'again')
  press('left', at - 1)
  eq(Pipelines.level('voxel'), 1, 'and LEFT goes back')

  -- nothing registered means nothing spliced: a vanilla install sees the
  -- list it always had
  Pipelines.install({ render_pipelines = {} })
  eq(#g:optionMenuSpec(), vanilla, 'with no pipelines the list is unchanged')
end)()

-- the ui.options.rows hook, and the arity that broke it
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  local rows = g:optionExtraRows()
  check(type(rows) == 'table', 'the extra rows resolve to a table')
  -- The hook takes a fallback of (game, rows) returning the ROWS. Returning
  -- the first argument instead hands back the GAME -- which is a table, passes
  -- the type check, and silently wipes the list. That is exactly what
  -- happened, and the symptom was a pipeline row that never appeared.
  local Pipelines = require('src.render.Pipelines')
  Pipelines.install({ render_pipelines = {
    p = { id = 'p', label = 'P', present = function() end,
      levels = { 'OFF', 'ON' } } } })
  local got = g:optionExtraRows()
  eq(#got, 1, 'a registered pipeline survives the hook rather than being lost')
  eq(got[1].id, 'pipeline:p', 'as itself')
  Pipelines.install({ render_pipelines = {} })
end)()

-- and src.ui.OptionsMenu resolves, so a mod patching it does not throw
;(function()
  check(Gen3Compat.serves('src.ui.OptionsMenu'),
    'the name a mod patches resolves instead of throwing')
  local g = Game3.new()
  pcall(function() g:load() end)
  Gen3Compat.bind(function() return g end)
  local OM = Gen3Compat.resolve('src.ui.OptionsMenu', 'test')
  eq(type(OM.new), 'function', 'it can be constructed')
  local menu = OM.new(g)
  check(type(menu.rows) == 'table', 'and answers a row list')
  check(pcall(menu.update, menu, 1 / 60),
    'update is a no-op rather than a nil call: Ruby rebuilds its option spec '
    .. 'every frame, so the stale-list problem the wrapper fixes cannot occur')
  -- the mod stamps a marker on the module to avoid double-wrapping
  OM.dramaticShapeFullHook = true
  eq(OM.dramaticShapeFullHook, true,
    'and a mod can stamp its own marker on it')
end)()




-- --------------------------- drawFx projects standing emotes
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 2, height = 2, grid = { 1, 2, 3, 4 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = g.data.sprites or {}
  g.playerX, g.playerY, g.facing = 1, 1, 'south'
  g.npcByMap = {}
  g.camX, g.camY = 0, 0
  g.emote = 'exclaim'
  local realG = love.graphics
  love.graphics = setmetatable({
    push = function() end,
    pop = function() end,
    scale = function() end,
    translate = function() end,
    setColor = function() end,
    draw = function() end,
  }, { __index = realG })
  local ctx = g:worldPipelineContext(2, 'voxel')
  local seen = {}
  local ok = pcall(ctx.drawFx, function(wx, wy)
    seen[#seen + 1] = { wx, wy }
    return wx, wy
  end, 2)
  love.graphics = realG
  check(ok, 'drawFx with a live emote does not throw')
  check(#seen >= 1, 'drawFx projects at least the player emote foot')
  eq(seen[1][1], 1 * 16 + 8, 'projected world X is the cell foot')
  eq(seen[1][2], 1 * 16 + 16, 'projected world Y is the cell foot')
end)()


-- --------------------------- VOXEL FULL via OPTION (not hotkey 3)
;(function()
  local Pipelines = require('src.render.Pipelines')
  local Input = require('src.core.Input')
  Input:init()
  local g = Game3.new()
  pcall(function() g:load() end)
  if g.modOptionsStore then g:modOptionsStore() end
  Pipelines.install({ render_pipelines = {
    voxel = { id = 'voxel', label = 'VOXEL', hotkey = '3',
      drawWorld = function() end,
      levels = { 'OFF', 'FULL', '15', '35' } } } })
  Pipelines.setLevel('voxel', 0)
  local spec = g:optionMenuSpec()
  local at
  for i, row in ipairs(spec) do
    if row[3] == 'extra:pipeline:voxel' then at = i end
  end
  check(at ~= nil, 'VOXEL row is on OPTION')
  local function press(key, cursor)
    g.field = { kind = 'option', cursor = cursor }
    local old = Input.wasPressed
    Input.wasPressed = function(_, k) return k == key end
    g:stepOptionMenu(g.field, function() end)
    Input.wasPressed = old
  end
  press('right', at - 1)
  eq(Pipelines.level('voxel'), 1, 'RIGHT from OFF lands on FULL')
  eq(g:optionMenuSpec()[at][2], 'FULL', 'and the row label reads FULL')
  check(g.save and g.save.options and g.save.options.pipelines
    and g.save.options.pipelines.voxel == 1,
    'FULL is synced into save.options.pipelines')
  check(type(g.optionAllDescriptors) == 'function',
    'optionAllDescriptors publishes cart+pipelines for the hook')
  local all = g:optionAllDescriptors()
  local hasTilt, hasVoxel = false, false
  for _, row in ipairs(all) do
    if row.id == 'tilt' then hasTilt = true end
    if row.id == 'pipeline:voxel' then hasVoxel = true end
  end
  check(hasTilt and hasVoxel,
    'hook input carries both TILT and VOXEL before a mod drops either')
end)()

-- ------------------- the sheet is handed over in the CONTRACT's frame
--
-- A consumer of bakeLayer works out which metatile a pixel belongs to from the
-- coordinates it is handed:
--
--   m = floor(y / 16) * SHEET_COLS + floor(x / 16)
--
-- and SHEET_COLS is SIXTEEN, hard-coded on both sides of that calculation --
-- it is the width the other engine's Gen3Tiles bakes to. Ruby's importer lays
-- a pair out THIRTY-TWO metatiles wide, so handing over our own coordinates
-- made every row past the first alias onto the next row's ids: 32 arriving as
-- 16, 33 as 17. On screen that was a chequerboard of mismatched ground across
-- every outdoor map.
--
-- This replays the consumer's own arithmetic against what we emit, which is
-- the only check that actually settles it -- asserting our own numbers back
-- to ourselves would have passed the whole time.
;(function()
  local Gen3Sheets = require('src.render.Gen3Sheets')
  Gen3Sheets.invalidate()

  -- a 32-wide stand-in atlas where every metatile is painted with its own id
  local W, H = 32 * 16, 2 * 16
  local img = {
    getDimensions = function() return W, H end,
    getPixel = function(_, x, y)
      local m = math.floor(y / 16) * 32 + math.floor(x / 16)
      return m / 255, 0, 0, 1
    end,
  }
  local realImage, realFs = love.image, love.filesystem
  love.image = { newImageData = function() return img end }
  love.filesystem = { getInfo = function() return { type = 'file' } end }
  local data = { tilesets = { atlasCols = 32, atlasRows = 2,
    byId = { t = { id = 't', bottom = 'b.png', behavior = {} } } } }

  local rec = Gen3Sheets.forTileset({ id = 't', blockTiles = 2 }, data)
  check(rec ~= nil, 'the sheet bakes')
  local cols, rows, w, h = rec.tiles:sheetLayout()
  eq(cols, 16, 'sheetLayout reports the CONTRACT width, not our atlas width')
  eq(rows, 4, 'and enough rows for all 64 metatiles at that width')
  eq(w, 256, 'with matching pixel dimensions')
  eq(h, 64, 'both ways')
  eq(rec.width, w, 'and the record agrees with the layout it publishes')
  eq(rec.cols, cols, 'both ways')

  -- THE CONSUMER'S OWN MATH, replayed
  local SHEET_COLS = 16
  local seen = {}
  rec.tiles:bakeLayer(1, function(x, y, r)
    local m = math.floor(y / 16) * SHEET_COLS + math.floor(x / 16)
    local id = math.floor(r + 0.5)
    if seen[m] == nil then seen[m] = id
    elseif seen[m] ~= id then seen[m] = 'MIXED' end
  end)
  local count, wrong = 0, 0
  for m, id in pairs(seen) do
    count = count + 1
    if id ~= m then wrong = wrong + 1 end
  end
  eq(count, 64, 'the consumer resolves every metatile in the atlas')
  eq(wrong, 0,
    'and each one lands on its OWN id -- a 32-wide emit puts metatile 32 at '
    .. 'id 16 and scrambles everything after it')

  love.image, love.filesystem = realImage, realFs
  Gen3Sheets.invalidate()
end)()


-- ------------------------- two sizes, and why collapsing them broke
--
-- A pipeline is handed two different measurements:
--
--   vw / vh          the world view, in WORLD pixels -- 240x160, the GBA's
--                    own view, whatever window it is shown in
--   width / height   the PLAYFIELD, in SCREEN pixels -- what a pipeline sizes
--                    its canvas and projection from
--
-- Gen 1 keeps them apart: `width = pw, height = ph` from playfieldRect, beside
-- its own vw/vh. I published 240x160 for both, which happens to look right in
-- a desktop window of roughly that shape -- and on a tall portrait phone put
-- the whole diorama in the bottom corner of a mostly empty screen.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 4, height = 4,
    grid = { 1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  g.viewW, g.viewH = 240, 160

  -- a tall portrait playfield, the shape a phone gives
  local ctx = g:worldPipelineContext(3, 'voxel', 720, 1280)
  eq(ctx.vw, 240, 'the world view stays the GBA view')
  eq(ctx.vh, 160, 'both ways')
  eq(ctx.width, 720, 'while width is the real playfield')
  eq(ctx.height, 1280, 'and height with it')
  check(ctx.width ~= ctx.vw,
    'the two are genuinely different on a portrait screen -- which is where '
    .. 'collapsing them showed up')

  -- and a landscape one, to prove it follows rather than being hard-coded
  local wide = g:worldPipelineContext(3, 'voxel', 1920, 1080)
  eq(wide.width, 1920, 'a landscape playfield comes through as itself')
  eq(wide.height, 1080, 'both ways')
  eq(wide.vw, 240, 'with the world view unchanged')

  -- nothing given: fall back to the world view rather than to nil, so a
  -- caller that never passes a size still gets usable numbers
  local bare = g:worldPipelineContext(3, 'voxel')
  eq(bare.width, 240, 'with no playfield given it falls back to the view')
  eq(bare.height, 160, 'both ways')
end)()

-- and the draw path actually passes them
;(function()
  local body = io.open('src/core/Game3.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  check(text:find('self:drawWorldBody(s, w, h)', 1, true) ~= nil,
    'the world draw hands the playfield size down rather than dropping it')
end)()

;(function()
  -- behaviourally too: what drawWorldBody passes is what a pipeline sees
  local Pipelines = require('src.render.Pipelines')
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  g.viewW, g.viewH = 240, 160
  g.drawWorldFlat = function() end
  g.worldPipelineId = function() return 'v' end
  local sawW, sawH, sawVw
  local realDraw = Pipelines.drawWorld
  Pipelines.drawWorld = function(_, ctx)
    sawW, sawH, sawVw = ctx.width, ctx.height, ctx.vw
    return nil
  end
  g:drawWorldBody(2, 800, 1600)
  Pipelines.drawWorld = realDraw
  eq(sawW, 800, 'the pipeline is handed the playfield width it was drawn at')
  eq(sawH, 1600, 'and the height')
  eq(sawVw, 240, 'with the world view still the world view')
end)()


-- ------------------------------------------- the canvas comes back in PIXELS
--
-- A pipeline sizes its scene from love.graphics.getPixelDimensions() and
-- allocates it with `dpiscale = 1` (the mod's own PixelCanvas.new), so the
-- image it returns is one texel per PHYSICAL pixel. This pass draws in
-- LOGICAL units -- GameViewport.dimensions() is love.graphics.getDimensions().
-- Blitting 1:1 therefore shows the top-left 1/dpi of the image, and because
-- the orbit's symmetric frustum puts its focus at the CENTRE of its own
-- canvas, the player and the only ground meshed around them land in the
-- lower right with the pipeline's cleared sky over the rest of the frame.
--
-- Gen 1 divides by the frame's dpi in Renderer:endFrame's worldOverride
-- branch. Deriving the factor from the canvas against the rect being filled
-- is the same number, and also right when render.viewport has reserved a
-- rectangle smaller than the window.
local function canvasStub(w, h)
  return {
    getPixelWidth = function() return w end,
    getPixelHeight = function() return h end,
    getWidth = function() return w end,
    getHeight = function() return h end,
  }
end

-- capture what love.graphics.draw is actually asked to do
local function captureDraw(fn)
  local G = love.graphics
  local realDraw = G.draw
  local seen = {}
  G.draw = function(img, x, y, r, sx, sy)
    seen[#seen + 1] = { img = img, x = x, y = y, r = r, sx = sx, sy = sy }
  end
  local ok, err = pcall(fn)
  G.draw = realDraw
  if not ok then error(err, 0) end
  return seen
end

;(function()
  local g = Game3.new()

  -- dpi 2: a 1440x2560 image onto a 720x1280 playfield
  local seen = captureDraw(function()
    check(g:presentWorldCanvas(canvasStub(1440, 2560), 720, 1280),
      'a measurable canvas is presented')
  end)
  eq(#seen, 1, 'exactly one blit, not a blit plus a stray')
  eq(seen[1].x, 0, 'at the target origin')
  eq(seen[1].y, 0, 'both ways')
  eq(seen[1].sx, 0.5, 'scaled by the canvas-to-playfield ratio, which is 1/dpi')
  eq(seen[1].sy, 0.5, 'both ways')

  -- dpi 1, the ordinary desktop case: an exact 1:1 blit, unchanged
  local flat = captureDraw(function()
    g:presentWorldCanvas(canvasStub(720, 1280), 720, 1280)
  end)
  eq(flat[1].sx, 1, 'a canvas that already matches is drawn 1:1')
  eq(flat[1].sy, 1, 'both ways')

  -- the case Gen 1 has no equivalent of: render.viewport reserved a
  -- rectangle SMALLER than the window, so the pipeline measured a window we
  -- are not filling. A fixed 1/dpi would overshoot the viewport here.
  local inset = captureDraw(function()
    g:presentWorldCanvas(canvasStub(720, 1280), 360, 640)
  end)
  eq(inset[1].sx, 0.5, 'a viewport smaller than the window scales to the '
    .. 'viewport, not to the window')
  eq(inset[1].sy, 0.5, 'both ways')
  check(inset[1].sx ~= flat[1].sx,
    'which is a different answer from the 1:1 case -- this fixture can tell '
    .. 'the two apart')
end)()

-- a canvas that cannot be measured is DECLINED rather than drawn blind: the
-- caller then falls through to the cartridge's own pass, so the world is
-- wrong-looking at worst and never blank
;(function()
  local g = Game3.new()
  eq(g:presentWorldCanvas(nil, 720, 1280), false, 'nil is not presentable')
  eq(g:presentWorldCanvas({}, 720, 1280), false,
    'nor is something with no dimensions to read')
  eq(g:presentWorldCanvas(canvasStub(0, 0), 720, 1280), false,
    'nor a zero-sized one, which would divide by zero')
  local threw = { getPixelWidth = function() error('no') end }
  eq(g:presentWorldCanvas(threw, 720, 1280), false,
    'nor one whose measurement throws')
end)()

-- and the whole draw path, end to end: a pipeline returns a pixel-sized
-- canvas and what reaches the screen is scaled to the playfield
;(function()
  local Pipelines = require('src.render.Pipelines')
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 1, height = 1, grid = { 1 }, tileset = 't',
    mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  g.viewW, g.viewH = 240, 160
  local flatRan = false
  g.drawWorldFlat = function() flatRan = true end
  g.worldPipelineId = function() return 'v' end

  local realDraw = Pipelines.drawWorld
  local realPresent = Pipelines.worldPresent
  Pipelines.drawWorld = function() return canvasStub(1440, 2560) end
  Pipelines.worldPresent = function(c) return c end
  local seen = captureDraw(function() g:drawWorldBody(2, 720, 1280) end)
  Pipelines.drawWorld, Pipelines.worldPresent = realDraw, realPresent

  eq(flatRan, false, 'a pipeline that returned a canvas owns the world pass')
  eq(#seen, 1, 'and its canvas is the one thing blitted')
  eq(seen[1].sx, 0.5,
    'scaled from its own pixel size onto the playfield it was drawn at')
  eq(seen[1].sy, 0.5, 'both ways')
end)()

-- vw/vh is the world the WINDOW covers, not a fixed 240x160.
--
-- syncWorldView divides the window by the zoom scale, and the mod's camera
-- frames exactly vh world pixels (Voxel3D.viewProjection's `dist = FOCAL *
-- vh`) while its dither grid is cut to w/vw. Pinning these to the GBA's own
-- 240x160 would frame a fifth of a tall phone's view and magnify the diorama
-- to match -- which is why the field is read off the live view, not named.
;(function()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  g.map = { id = 'M', width = 4, height = 4,
    grid = { 1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1 },
    tileset = 't', mapType = Game3.MAP_TYPE_ROUTE }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.playerX, g.playerY, g.facing = 0, 0, 'south'
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end

  -- the shape a phone at 3x gives: 240 across, far more than 160 down
  g.viewW, g.viewH = 240, 534
  local tall = g:worldPipelineContext(3, 'voxel', 720, 1602)
  eq(tall.vh, 534, 'vh follows the live view rather than the GBA constant')
  check(tall.vh ~= Game3.SCREEN_H,
    'and on a portrait window that is emphatically not 160')
  -- the two numbers a pipeline derives from vh, restated here so a change
  -- that quietly pins vh shows up as a wrong camera rather than a wrong field
  eq(tall.height / tall.vh, 3, 'height over vh is the zoom -- pixels per '
    .. 'world pixel, which is what the sky and water cut their dither to')
  eq(tall.width / tall.vw, 3, 'and the same number across, so the grid is '
    .. 'square')
end)()


-- ---------------------------------------- neighbours are placed in PIXELS
--
-- `state.neighbors[i].ox/oy` is where a connected map sits relative to this
-- one, and the contract is WORLD PIXELS. Gen 1 builds them that way outright
-- (`ox = conn.offset * 32`, a Gen 1 block being 32px) and a mesher translates
-- the neighbour's geometry by them into a mesh whose own coordinates are
-- world pixels: `Mat4.translate(nb.ox, 0, nb.oy)`.
--
-- Game3:connectedLayout answers in CELLS -- its own comment says "Origins are
-- in the current map's tile space", and Game3's draw multiplies by
-- Game3.TILE to place one. Publishing those numbers unconverted put every
-- neighbour at a sixteenth of its distance, stacked on top of the map the
-- player was standing on.
--
-- The fixture keeps cells and pixels in disjoint ranges so no assertion can
-- pass on the wrong one: a 20x12 map with a neighbour 12 cells up is at
-- oy = -192 px, and -12 is nowhere near it.
local function nbGame()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  local function blank(n)
    local t = {}
    for i = 1, n do t[i] = 1 end
    return t
  end
  -- north neighbour: 20 wide, 12 tall, so it sits at oy = -12 cells
  local north = { id = 'g1_1', tileset = 't', mapType = Game3.MAP_TYPE_ROUTE,
    width = 20, height = 12, grid = blank(240), border = { 1, 1, 1, 1 },
    connections = { { dir = 'south', offset = 0, mapGroup = 1, mapNum = 2 } } }
  -- the map underfoot: 20 wide, 20 tall, connected north to the above
  local here = { id = 'g1_2', tileset = 't', mapType = Game3.MAP_TYPE_TOWN,
    width = 20, height = 20, grid = blank(400), border = { 1, 1, 1, 1 },
    connections = { { dir = 'north', offset = 0, mapGroup = 1, mapNum = 1 } } }
  g.data.maps = { maps = { g1_1 = north, g1_2 = here } }
  g.data.tilesets = { byId = { t = { behavior = {}, layerType = {},
    metatileCount = 1024 } }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.map = here
  g.playerX, g.playerY, g.facing = 10, 10, 'south'
  g.camX, g.camY = 0, 0
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  return g, here, north
end

;(function()
  local g, here, north = nbGame()
  local ow = g:modOverworld()
  check(ow ~= nil, 'the overworld view builds with a connection in place')
  eq(#ow.neighbors, 1, 'the connected map is published as a neighbour')
  local nb = ow.neighbors[1]
  eq(nb.map.id, 'g1_1', 'and it is the map the connection names')

  -- the engine's own answer, in cells, which is what we start from
  local cells
  for _, row in ipairs(g:mapPlacements(here)) do
    if row.map ~= here then cells = row end
  end
  check(cells ~= nil, 'the engine places it too')
  eq(cells.oy, -12, "connectedLayout answers in CELLS -- the neighbour's own "
    .. 'height above this map')

  -- and the published value is those cells in pixels
  eq(nb.oy, -192, 'the published offset is world pixels: 12 cells at 16px')
  eq(nb.ox, 0, 'and a zero offset stays zero either way')
  check(nb.oy ~= cells.oy,
    'the two are genuinely different numbers -- this fixture cannot pass on '
    .. 'the unconverted one')
  eq(nb.oy / cells.oy, Game3.TILE, 'the factor is the metatile size exactly')
end)()

-- THE CONSEQUENCE, stated the way the mesher states it. VoxelScene builds a
-- neighbour's mask as { ox, oy, ox + width * px, oy + height * px } and
-- expects it to ABUT this map, not to lie on top of it. Restating the mod's
-- own arithmetic here is what makes this a test of the bug rather than of
-- the line I wrote: with cells published, the north neighbour's rect fell
-- entirely inside the body of the map underfoot.
;(function()
  local g, here = nbGame()
  local nb = g:modOverworld().neighbors[1]
  local px = (tonumber(nb.map.tileset and nb.map.tileset.blockTiles) or 4) * 8
  eq(px, 16, "a Gen 3 block is 16px, which is what the mod's fallback derives")
  local x0, y0 = nb.ox, nb.oy
  local x1, y1 = nb.ox + nb.map.def.width * px, nb.oy + nb.map.def.height * px
  eq(y1, 0, "the north neighbour's bottom edge meets this map's top edge")
  eq(y0, -192, 'and its top edge is its own height above that')
  eq(x0, 0, 'flush on the left')
  eq(x1, 320, 'and 20 cells wide in pixels')

  -- this map's own body, in the same units
  local hereX1, hereY1 = here.width * px, here.height * px
  eq(hereY1, 320, 'the map underfoot is 20 cells tall in pixels')
  check(y1 <= 0, 'the neighbour is entirely ABOVE this map, not over it')
  check(not (y0 < hereY1 and y1 > 0 and x0 < hereX1 and x1 > 0),
    'the two rectangles do not overlap at all -- which is the whole '
    .. 'complaint: neighbouring maps drawn on top of the one underfoot')
end)()


-- ------------------------------- a ghost's offset is world pixels, like the
-- neighbour offset it comes from.
--
-- `posesOf` places one as `px = vx + g.ox, py = g.npc.py + g.oy`, where vx and
-- npc.py are the sprite's own PIXEL position; Gen 1 fills ox/oy from the same
-- pixel offset its neighbour list carries (OverworldController's ghost row is
-- `ox = nb.ox`). Publishing cells put every person on a connected route at a
-- sixteenth of their distance -- which is inside the city the player is
-- standing in.
;(function()
  local g, here, north = nbGame()
  -- put two people on the neighbour and one here, so the two lists cannot be
  -- confused for each other
  g.npcByMap = {
    [here.id] = { { id = 'local1', x = 3, y = 4, graphicsId = 0 } },
    [north.id] = { { id = 'far1', x = 5, y = 6, graphicsId = 0 },
                   { id = 'far2', x = 7, y = 8, graphicsId = 0 } },
  }
  local ow = g:modOverworld()
  eq(#ow.npcs, 1, 'the map underfoot contributes its own cast')
  eq(#ow.entities, 2, 'entities is that cast plus the player')
  eq(#ow.ghosts, 2, "and the neighbour's people are ghosts")

  local ghost = ow.ghosts[1]
  eq(ghost.oy, -192, "a ghost carries the neighbour's offset in WORLD PIXELS")
  eq(ghost.ox, 0, 'and zero stays zero')
  check(ghost.oy ~= -12,
    'not the cell offset -- which is what put a hundred people in Mauville')

  -- the arithmetic the renderer performs, restated: a person standing at
  -- cell (5,6) on the map to the north is at y = 6*16 - 192 = -96, which is
  -- ABOVE this map, not inside it
  local py = 6 * Game3.TILE + ghost.oy
  eq(py, -96, "the ghost lands on its own map, north of this one")
  check(py < 0, 'which is outside the body of the map underfoot entirely')

  -- and modActorLists, the other publisher of the same thing, agrees
  local lists = g:modActorLists()
  eq(#lists.ghosts, 2, 'modActorLists sees the same two')
  eq(lists.ghosts[1].oy, ghost.oy,
    'and offsets them the same way -- the two publishers cannot disagree')
end)()

-- ------------------------------------- the map view is ONE table per map
--
-- The mod caches its entire Gen 3 context as `ctxCache[map]`, keyed by the
-- view table's identity, and rebuilding that table every frame meant the
-- cache never hit: it re-derived the context, and buildElevationRanks over
-- every cell with it, once per frame per map. Our own side was worse --
-- defView materialises a collision and an elevation entry per cell, and the
-- camera moving invalidates the outer cache every frame a player walks.
;(function()
  local g = nbGame()
  local a = g:modMapView(g.map)
  local b = g:modMapView(g.map)
  check(a == b, 'the same map yields the SAME view table, so a mod keyed on '
    .. 'its identity can cache against it')

  -- and it survives the camera moving, which is what happens every frame
  local first = g:modOverworld().map
  g.camX, g.camY = (g.camX or 0) + 7, (g.camY or 0) + 3
  local second = g:modOverworld().map
  check(first == second, 'walking does not hand the mod a new map table')

  -- still LIVE, not a snapshot: the methods read the grid on every call
  local before = g.map.grid[1]
  eq(second:blockAt(0, 0), Game3.metatileOf(before), 'blockAt reads the grid')
  g.map.grid[1] = before + 5
  eq(second:blockAt(0, 0), Game3.metatileOf(before + 5),
    'and follows a write with no rebuild -- the view is reused, not frozen')
  g.map.grid[1] = before

  -- the two eager PLANES are snapshots, so a cell write bumps a revision and
  -- the view is rebuilt. Without it a door would open on screen and stay
  -- shut in the mesh.
  local held = g:modOverworld().map
  Game3.noteGridWrite(g.map)
  local after = g:modOverworld().map
  check(held ~= after, 'a recorded grid write rebuilds the view')
  eq(g.map._gridRev, 1, 'and the revision counts it')
end)()

-- every engine path that writes a cell records it
;(function()
  local body = io.open('src/core/Game3.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  local writes, notes = 0, 0
  for _ in text:gmatch('map%.grid%[[^%]]*%]%s*=') do writes = writes + 1 end
  for _ in text:gmatch('Game3%.noteGridWrite%(') do notes = notes + 1 end
  check(writes > 0, 'the engine does write cells')
  -- one definition plus one call per write site
  eq(notes, writes + 1,
    'every map.grid write is paired with a noteGridWrite, or the two planes '
    .. 'a mod reads go stale behind it')
end)()


-- --------------------------------------------- the walk has a seam now
--
-- Gen 1 keeps the grid walk's only keypad read in
-- OverworldController:handleInput, and the voxel mod replaces the walk by
-- wrapping exactly that -- so every gate above the call (scripted moves,
-- forced movement, a warp settle, a field UI) still applies without the mod
-- restating any of it.
--
-- Ruby had the block inline in walkHeld, which is not a seam and could not
-- be made one by wrapping walkHeld: that method also ticks berry trees,
-- grass rustle, the tileset animation, cracked floors, screen fades and door
-- animation, and a mod replacing the walk would have stopped all of them.
local function seamGame()
  local g = Game3.new()
  pcall(function() g:load() end)
  g.phase = 'play'
  local grid = {}
  for i = 1, 400 do grid[i] = 1 end
  g.map = { id = 'M', width = 20, height = 20, grid = grid, tileset = 't',
    border = { 1, 1, 1, 1 }, mapType = Game3.MAP_TYPE_TOWN }
  g.data.tilesets = { byId = { t = {} }, atlasCols = 32, atlasRows = 32 }
  g.data.sprites = { byId = {} }
  g.playerX, g.playerY, g.facing = 5, 5, 'south'
  g.camX, g.camY = 0, 0
  g.npcByMap = {}
  g.playerGraphicsId = function() return 0 end
  return g
end

;(function()
  check(type(Game3.gridHandleInput) == 'function',
    "Ruby's own pad read is its own method")
  check(type(Game3.fieldHandleInput) == 'function',
    'and the walk reaches it through a seam')

  -- THE SHARED TABLE is the whole point: a wrap installed on the copy the
  -- mod resolves has to be the one the engine calls. This is the lesson the
  -- voxel hotkey taught -- a mod wrapped a method on the facade while Game3
  -- went on calling its own, and the hotkey silently did nothing.
  local modCopy = Gen3Compat.resolve('src.world.OverworldController', 'test')
  local engineCopy = require('src.world.gen3.OverworldAPI')
  check(modCopy ~= nil, 'the controller module resolves on Ruby')
  check(modCopy == engineCopy,
    'and the mod and the engine hold the SAME table, so a wrap on one is '
    .. 'the function the other calls')
  eq(Gen3Compat.memberStatus('src.world.OverworldController', 'handleInput'),
    'backed', 'handleInput is backed')
  eq(Gen3Compat.memberStatus('src.world.OverworldController', 'checkEdgeExit'),
    nil, 'the push verbs are NOT on this module -- they are called on the '
    .. 'state, and claiming them here is what crashed a free walk at a map '
    .. 'edge')

  -- THE PLAYER WRITES BACK, which is what serving the name depends on: the
  -- contract for replacing the walk is that a mod moves the player by
  -- assigning to the fields it read.
  local g2 = seamGame()
  local p = g2:modOverworld().player
  p.cellX, p.cellY, p.facing = 9, 11, 'north'
  eq(g2.playerX, 9, 'a write to the player view reaches the engine')
  eq(g2.playerY, 11, 'in both axes')
  eq(g2.facing, 'north', 'and the facing with it')
  -- px/py are world pixels and drive the CONTINUOUS position
  p.px, p.py = 9 * 16 + 8, 11 * 16 + 4
  local vx, vy = g2:visualTile()
  eq(vx, 9.5, 'visualTile answers the free walk in fractional cells')
  eq(vy, 11.25, 'both ways')
  -- and only the named fields cross over
  p.somethingOfItsOwn = 'mine'
  eq(g2.somethingOfItsOwn, nil,
    'a field the contract does not name stays on the view')
  eq(p.somethingOfItsOwn, 'mine', 'and reads back from it')
  -- the grid walk takes the position back
  g2:gridHandleInput()
  local bx = g2:visualTile()
  eq(bx, 9, 'the grid walk drops the free position and lerps its own again')

  -- the two callbacks a replaced walk uses instead of reimplementing them
  local ow2 = g2:modOverworld()
  check(type(ow2.interact) == 'function', 'interact is published')
  check(type(ow2.onStepComplete) == 'function', 'and onStepComplete')
  local talked, arrived = 0, 0
  g2.tryTalk = function() talked = talked + 1 return true end
  g2.stepArrived = function() arrived = arrived + 1 return false end
  ow2:interact()
  ow2:onStepComplete()
  eq(talked, 1, "interact is Ruby's own A-button handler")
  eq(arrived, 1, 'and onStepComplete its own landing pipeline')
end)()

-- a wrap is genuinely in the path, and is handed the overworld view
;(function()
  local API = require('src.world.gen3.OverworldAPI')
  local g = seamGame()
  local inner = API.handleInput
  local seen, got = 0, nil
  API.handleInput = function(state) seen = seen + 1 got = state
    return inner(state) end
  local own = 0
  g.gridHandleInput = function() own = own + 1 end
  g:fieldHandleInput()
  API.handleInput = inner

  eq(seen, 1, 'the engine called through the module a mod wraps')
  eq(own, 1, "and the wrap fell through to Ruby's own walk")
  check(got ~= nil, 'the wrap was handed a state')
  eq(got.isOverworld, true,
    'which is the overworld view, the object Gen 1 passes -- not the game')
  check(got.player ~= nil, 'so it has the player a free walk moves')
  check(got.map ~= nil, 'the map it asks about passability')
  check(got.entities ~= nil, 'and the cast it tests occupancy against')
end)()

-- a mod that REPLACES the walk stops the grid walk, which is the point
;(function()
  local API = require('src.world.gen3.OverworldAPI')
  local g = seamGame()
  local inner = API.handleInput
  API.handleInput = function() return true end        -- "I own the walk"
  local own = 0
  g.gridHandleInput = function() own = own + 1 end
  g:fieldHandleInput()
  API.handleInput = inner
  eq(own, 0, 'a mod that owns the walk suppresses the grid walk entirely')
end)()

-- and walkHeld actually routes through it, rather than still reading the pad
-- inline. A behavioural check: drive walkHeld and see the seam fire.
;(function()
  local API = require('src.world.gen3.OverworldAPI')
  local g = seamGame()
  local inner = API.handleInput
  local seen = 0
  API.handleInput = function(state) seen = seen + 1 return inner(state) end
  pcall(function() g:walkHeld(1 / 60) end)
  API.handleInput = inner
  check(seen > 0,
    "walkHeld's pad read goes through the seam -- not still inline, which "
    .. 'is what a mod could not reach')
end)()

-- The module carries handleInput and NOTHING ELSE. The push verbs used to be
-- stubbed here, which was the bug: they are called on the state, so a stub on
-- this table answered nobody while reading as though the case was handled.
;(function()
  local API = require('src.world.gen3.OverworldAPI')
  check(type(API.handleInput) == 'function', 'handleInput is the seam')
  eq(API.checkEdgeExit, nil,
    'and the push verbs are not claimed here -- a refusal on the wrong '
    .. 'object is worse than no refusal, because it looks handled')
  eq(API.UNIMPLEMENTED, nil, 'nor is a list of them')
end)()


-- collision: the ONE generation-agnostic function is backed, the rest refuse
;(function()
  local C = Gen3Compat.resolve('src.world.Collision', 'test')
  check(C ~= nil, 'src.world.Collision resolves on Ruby')
  check(C == require('src.world.gen3.Collision'), 'to the Gen 3 adapter')
  eq(Gen3Compat.memberStatus('src.world.Collision', 'occupied'), 'backed',
    'occupied is backed -- it reads only the entity list it is handed')
  eq(Gen3Compat.memberStatus('src.world.Collision', 'canMove'), 'warned',
    "and canMove is not: Gen 1's verdict reads block tables Ruby lacks")

  local a = { cellX = 3, cellY = 4 }
  local b = { cellX = 9, cellY = 9, targetX = 5, targetY = 6 }
  local me = { cellX = 1, cellY = 1 }
  local list = { a, b, me }
  eq(C.occupied(list, 3, 4), a, 'an actor standing on the cell occupies it')
  eq(C.occupied(list, 5, 6), b,
    'and one STEPPING INTO it does too -- the reservation, so two bodies '
    .. 'cannot converge on one cell')
  eq(C.occupied(list, 7, 7), nil, 'an empty cell is free')
  eq(C.occupied(list, 1, 1, me), nil,
    'and the asker never blocks itself, so it can always leave where it is')
  local through = { cellX = 2, cellY = 2, passable = true }
  eq(C.occupied({ through }, 2, 2), nil, 'a walk-through actor does not block')
  eq(C.occupied(nil, 1, 1), nil, 'and no list is no occupancy, not a throw')
  eq(C.canMove(), nil, 'the refusing verbs answer nil rather than guessing')
end)()


-- ---------------- the free walk survives the view being rebuilt
--
-- THE BUG THIS EXISTS FOR. The overworld view is rebuilt whenever its cache
-- signature moves, and camX/camY are in that signature -- so on a real map,
-- where the camera follows the player every frame, it is rebuilt every frame.
-- The write-through store lived on the proxy, so it was empty again each
-- time.
--
-- A continuous walk reads back the position it wrote to find out whether
-- something else moved the player (`if p.px ~= lastPx then adopt(p) end`).
-- Reading back the SNAPPED cell looks exactly like that, so it re-adopted the
-- cell centre every frame and discarded the pixel it had just covered: the
-- body creeps and never crosses a cell. On a phone the d-pad looked dead in
-- first person; a desk harness with a still camera walked fine, which is
-- exactly why the first version of these tests passed.
;(function()
  local g = seamGame()
  local p = g:modOverworld().player
  p.px, p.py = 5 * 16 + 6, 5 * 16 + 2
  eq(p.px, 86, 'the walk reads back the position it just wrote')

  -- the camera follows the player: the view rebuilds
  g.camX = (g.camX or 0) + 1
  local p2 = g:modOverworld().player
  check(p2 ~= p, 'the view really was rebuilt -- this fixture reproduces the '
    .. 'device condition rather than a still camera')
  eq(p2.px, 86, 'and the free-walk position survives the rebuild')
  eq(p2.py, 82, 'in both axes')

  -- which is what keeps a walk accumulating instead of re-snapping
  for i = 1, 8 do
    local q = g:modOverworld().player
    q.px = q.px + 2
    g.camX = g.camX + 1
  end
  eq(g:modOverworld().player.px, 102,
    'eight frames of two pixels each accumulate to sixteen -- a whole cell '
    .. 'crossed, which a re-snapping body never manages')

  -- and a mod's own bookkeeping on the actor survives too
  g:modOverworld().player.myOwnField = 'kept'
  g.camX = g.camX + 1
  eq(g:modOverworld().player.myOwnField, 'kept',
    'a field the contract does not name still persists across a rebuild')
  eq(g.myOwnField, nil, 'without leaking onto the engine')

  -- the grid walk still takes it all back
  g:gridHandleInput()
  local bx = g:visualTile()
  eq(bx, 5, 'and the grid walk drops the free position')
  eq(g:modOverworld().player.px, 80,
    'so the player reads back on its cell again')
end)()


-- ------------------------------- the blocked-push verbs, ON THE STATE
--
-- THE CRASH THIS EXISTS FOR. A free walk that pushes into something calls
-- `state:checkEdgeExit(dir)`. I had defined those on the controller MODULE,
-- which is never the object asked -- so the first time a free walk reached a
-- map edge it indexed nil and took the frame down inside the mod's own file.
-- Naming a refusal is only worth anything if it is named on the object that
-- gets asked.
local function edgeGame()
  local g, here, north = nbGame()
  g.playerX, g.playerY, g.facing = 5, 0, 'north'   -- on the top row
  return g, here, north
end

;(function()
  local ow = edgeGame():modOverworld()
  for _, name in ipairs({ 'checkEdgeExit', 'checkLedgeHop', 'checkBoulderPush',
                          'canCollisionWarp', 'takeWarp' }) do
    check(type(ow[name]) == 'function', name .. ' is on the STATE')
  end
end)()

-- UP IS NORTH. The mod API names directions for the d-pad and Ruby names them
-- for the compass, and deltaFromFacing answers SOUTH for anything it does not
-- recognise -- so an untranslated "up" does not fail, it quietly means down.
;(function()
  local g = edgeGame()
  local ow = g:modOverworld()
  eq(g.map.id, 'g1_2', 'the player starts on the southern map')
  eq(ow:checkEdgeExit('up'), true,
    'pushing north off the top row is a connection step')
  eq(g.map.id, 'g1_1', 'and the engine crossed into the connected map')
  eq(g.playerY, 11, "landing on the far map's bottom row")

  -- untranslated, "up" would have asked about the cell BELOW and declined
  local g2 = edgeGame()
  eq(g2:modOverworld():checkEdgeExit('down'), false,
    'pushing south from the top row is not an edge at all')
  eq(g2.map.id, 'g1_2', 'so nothing moved')

  -- and mid-map it declines rather than taking an ordinary step
  local g3 = edgeGame()
  g3.playerY = 10
  eq(g3:modOverworld():checkEdgeExit('up'), false,
    'inside the body this is not the edge verb\'s question')
  eq(g3.playerY, 10, 'and the player did not step')
end)()

-- the same translation on the facing the mod assigns every tick
;(function()
  local g = edgeGame()
  local p = g:modOverworld().player
  p.facing = 'up'
  eq(g.facing, 'north', "a mod's \"up\" is stored as Ruby's \"north\"")
  p.facing = 'right'
  eq(g.facing, 'east', 'and right is east')
  p.facing = 'west'
  eq(g.facing, 'west', 'a compass name passes through unchanged')
  -- the failure this prevents: an unrecognised name reads back as SOUTH from
  -- every one of Ruby's own direction readers, silently
  p.facing = 'sideways'
  eq(g.facing, 'west', 'an unrecognised name is dropped, not stored')
  local dx, dy = Game3.deltaFromFacing(g.facing)
  eq(dx, -1, 'so the engine still reads a real direction off it')
  eq(dy, 0, 'both ways')
end)()

-- ledges delegate to the engine's own hop rather than restating it
;(function()
  local g = edgeGame()
  local asked
  g.tryLedgeHop = function(_, map, dx, dy) asked = { dx, dy } return true end
  eq(g:modOverworld():checkLedgeHop('left'), true,
    'a ledge push reaches the engine handler')
  eq(asked[1], -1, 'with left translated to west')
  eq(asked[2], 0, 'both ways')
end)()

-- and the three Ruby cannot back refuse rather than throwing
;(function()
  local ow = edgeGame():modOverworld()
  eq(ow:checkBoulderPush('up'), false, 'boulders need the script VM')
  eq(ow:canCollisionWarp(), false, 'Gen 3 has no warp carpets')
  eq(ow:takeWarp({}), false, 'so nothing follows from one')
end)()


-- ------------------ a free walk's position does not survive a map change
--
-- THE SEAM THIS EXISTS FOR. freeWalkPx/Py are world pixels on the map the
-- walk was standing on; the new map has its own origin. Crossing Route 117's
-- east edge into Mauville carried them over, so the view sat forty cells east
-- of the player -- outside the body, looking at void fill. On screen that is
-- an endless sea of water at every seam, and the stall with it: the mesher
-- was asked for border ring over a vast empty region.
--
-- And it stranded the walk for good. A continuous walk re-adopts when what it
-- reads back is not what it wrote -- that is how it learns a warp moved the
-- player -- and a stale freeWalkPx reads back as exactly what it wrote.
;(function()
  local g, here, north = nbGame()
  g.playerX, g.playerY, g.facing = 5, 0, 'north'
  local ow = g:modOverworld()

  -- the free walk owns the position, a few pixels into the cell
  local wrote = 5 * 16 + 12
  ow.player.px, ow.player.py = wrote, 0
  eq(g.freeWalkPx, wrote, 'the walk is driving before the crossing')

  eq(ow:checkEdgeExit('up'), true, 'and it crosses the seam')
  eq(g.map.id, 'g1_1', 'onto the connected map')
  eq(g.freeWalkPx, nil,
    "the old map's pixel position is dropped, not carried across")

  -- which is what lets the walk notice at all
  local p = g:modOverworld().player
  check(p.px ~= wrote,
    'the walk reads back something other than what it wrote, so it '
    .. 're-adopts rather than walking on from the old map\'s coordinates')
  eq(p.px, g.playerX * Game3.TILE,
    'and what it reads is the cell it actually landed on')

  -- the camera follows the engine's own connection lerp, not a stale pixel
  g.walkCooldown = 0
  local vx, vy = g:visualTile()
  eq(vx, g.playerX, 'once the step settles the view is on the player')
  eq(vy, g.playerY, 'both ways')
end)()

-- every map change clears it, not just a connection: enterMap is the one
-- place self.map is assigned, so warps, falls and script teleports share it
;(function()
  local g = nbGame()
  g.freeWalkPx, g.freeWalkPy = 999, 888
  local other = g.data.maps.maps.g1_1
  pcall(function() g:enterMap(other, 2, 3) end)
  eq(g.freeWalkPx, nil, 'a warp drops the free position too')
  eq(g.freeWalkPy, nil, 'both axes')
end)()


-- --------------------------------- a Gen 3 door is a warp on a collision tile
--
-- Gen 1 warps a walk through a CARPET: canCollisionWarp gates it and
-- Warp.onCollision reads a carpet table. Ruby has no carpets -- its doors are
-- warp tiles the step is REFUSED by, and the warp fires from that refusal.
-- So a free walk pushing into the Pokemon Center is told "tile", asks the
-- four Gen 1 verbs, and every one of them correctly says no: the player
-- stands perfectly lined up with the door and nothing happens.
;(function()
  local g = nbGame()
  local map = g.map
  -- a door on the cell north of the player, the way a Center's is
  map.warps = { { x = 5, y = 4, id = 0, mapGroup = 1, mapNum = 1 } }
  g.playerX, g.playerY, g.facing = 5, 5, 'north'
  local ow = g:modOverworld()

  check(type(ow.checkDoorWarp) == 'function',
    'the Gen 3 shaped question is published under its own name')

  -- pushing into a cell with no warp is not this verb's business: it must
  -- not take an ordinary step on the walk's behalf
  local moved = 0
  g.tryWalk = function() moved = moved + 1 return true end
  eq(ow:checkDoorWarp('down'), false,
    'no warp on the cell pushed into means nothing to do here')
  eq(moved, 0, 'and tryWalk is not called, so no step is taken by accident')

  -- with a warp there, it hands the push to the engine's own door rules
  local asked
  g.tryWalk = function(_, dx, dy) asked = { dx, dy } return true end
  eq(ow:checkDoorWarp('up'), true, 'a warp on the pushed-into cell is taken')
  eq(asked[1], 0, 'with the direction translated to Ruby vocabulary')
  eq(asked[2], -1, 'up being north')

  -- and a refused warp reports refusal rather than swallowing the push
  g.tryWalk = function() return false end
  eq(ow:checkDoorWarp('up'), false,
    'a door the engine declines (locked, wrong direction, an NPC on the mat) '
    .. 'leaves the push for whatever else might handle it')
end)()

-- the mod asks for it only where it exists, so Gen 1 and Gen 2 are untouched
;(function()
  local f = io.open('C:/Users/Feces/AppData/Roaming/LOVE/pokemon-love2d/mods/'
    .. 'Gen2Recomped-DramaticShapes/lib/FreeMove.lua', 'r')
  if not f then
    check(true, '(the installed mod is not readable from here; skipped)')
    return
  end
  local text = f:read('*a')
  f:close()
  check(text:find('state.checkDoorWarp and state:checkDoorWarp(dir)', 1, true)
    ~= nil, 'the mod guards the call on the method existing')
  check(text:find('if state:checkDoorWarp(dir) then', 1, true) == nil,
    'and never calls it unguarded -- an unguarded call would crash on the '
    .. 'Gen 1 and Gen 2 engines this mod still has to run on')
end)()


-- --------------------- a walkable warp fires on ARRIVAL, by the ARRIVAL rule
--
-- field_control_avatar.c has TWO warp rules and they do not agree:
--
--   ARRIVAL   TryStartStepBasedScript -> TryStartWarpEventScript. A warp
--             event on the tile you are STANDING ON plus IsWarpMetatileBehavior
--             is the whole test. No direction gate.
--   A BUMP    TryDoorWarp, for walking INTO a door you cannot stand on.
--             Direction-gated: an animated door opens only walking north.
--
-- A Pokemon Center or Mart exit mat is WALKABLE and carries a door behaviour,
-- so it is an arrival. Asking the bump rules about it answered "bumped, wrong
-- direction" for every approach but north, and the player could not leave the
-- building -- which is exactly what a Mart did.
;(function()
  local g = nbGame()
  local map = g.map
  map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 } }
  g.data.tilesets.byId.t.behavior = { [1] = Game3.MB_ANIMATED_DOOR }
  g.playerX, g.playerY = 5, 6
  local followed = 0
  g.followWarp = function() followed = followed + 1 return true end

  -- every direction of approach, including the three the bump rule refuses
  for _, facing in ipairs({ 'south', 'north', 'east', 'west' }) do
    followed = 0
    g.facing = facing
    eq(g:tryWarpOnArrival(), true,
      'arriving on the mat facing ' .. facing .. ' takes the warp')
    eq(followed, 1, 'exactly once')
  end

  -- the bump rule, for contrast: it refuses an animated door from the south,
  -- which is right for walking INTO one and wrong for standing ON one
  local bumped = g:tryWarpStep(map, 5, 6, 0, 1)
  eq(bumped, false,
    'the bump rule refuses the same tile approached from the north -- the '
    .. 'two rules genuinely differ, which is the whole point')

  -- a tile with a warp but no warp BEHAVIOUR is not a warp: plain ground
  -- under a warp event happens, and stepping on it must not teleport you
  local g2 = nbGame()
  g2.map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 } }
  g2.data.tilesets.byId.t.behavior = {}
  g2.playerX, g2.playerY = 5, 6
  g2.followWarp = function() return true end
  eq(g2:tryWarpOnArrival(), false,
    'no warp behaviour on the tile means no warp, as IsWarpMetatileBehavior '
    .. 'says')

  -- and a coord event on the mat beats the warp, as in the cart, where
  -- TryStartCoordEventScript is the line above TryStartWarpEventScript
  local g3 = nbGame()
  g3.map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 } }
  g3.data.tilesets.byId.t.behavior = { [1] = Game3.MB_ANIMATED_DOOR }
  g3.playerX, g3.playerY = 5, 6
  g3.coordEventWouldRun = function() return true end
  g3.followWarp = function() return true end
  eq(g3:tryWarpOnArrival(), false, 'a doormat script beats the warp under it')
end)()

-- and the view fires it on every cell crossing, before the landing pipeline
;(function()
  local g = nbGame()
  local order = {}
  g.tryWarpOnArrival = function() order[#order + 1] = 'warp' return false end
  g.stepArrived = function() order[#order + 1] = 'arrived' return false end
  g:modOverworld():onStepComplete()
  eq(order[1], 'warp', 'the warp is asked first -- the cell may not be a '
    .. 'place to arrive at all')
  eq(order[2], 'arrived', 'then the ordinary landing pipeline')

  local g2 = nbGame()
  local arrived = 0
  g2.tryWarpOnArrival = function() return true end
  g2.stepArrived = function() arrived = arrived + 1 return false end
  eq(g2:modOverworld():onStepComplete(), true, 'a warp taken ends the step')
  eq(arrived, 0, 'and the landing pipeline does not run on a map being left')
end)()

-- THE TWO RULES ARE SEPARATE FUNCTIONS, deliberately.
--
-- tryWarpStep is the cart's TryDoorWarp: walking INTO a door, direction-gated.
-- tryWarpOnArrival is TryStartWarpEventScript: standing ON a warp tile, no
-- direction. An earlier version had arrival delegate to the bump rule, which
-- reads as reuse and is actually a different question -- it refused every
-- shop exit approached from anywhere but the north.
;(function()
  check(type(Game3.tryWarpStep) == 'function', 'the bump rule is its own')
  check(type(Game3.tryWarpOnArrival) == 'function', 'and so is the arrival')
  local body = io.open('src/core/Game3.lua', 'r')
  local text = body and body:read('*a') or ''
  if body then body:close() end
  check(text:find('self:tryWarpStep(map, nx, ny, dx, dy)', 1, true) ~= nil,
    'tryWalk asks the bump rule about the cell it is stepping INTO')
  local arrival = text:match('function Game3:tryWarpOnArrival.-\nend')
  check(arrival ~= nil, 'the arrival rule is readable')
  check(arrival:find('tryWarpStep', 1, true) == nil,
    'and does NOT delegate to the bump rule, which is the bug this pins')
  check(arrival:find('isWarpBehavior', 1, true) ~= nil,
    'it tests IsWarpMetatileBehavior, as the cart does')
  check(arrival:find('coordEventWouldRun', 1, true) ~= nil,
    'after coord events, as the cart does')
end)()


-- the world pass says which path it took, once per map per outcome
;(function()
  local Pipelines = require('src.render.Pipelines')
  local Logger = require('src.core.Logger')
  local g = seamGame()
  g.drawWorldFlat = function() end
  g.worldPipelineId = function() return 'v' end
  local said = {}
  local realInfo = Logger.info
  Logger.info = function(fmt, ...) said[#said + 1] = string.format(fmt, ...) end
  local realDraw = Pipelines.drawWorld
  Pipelines.drawWorld = function() return nil end          -- declines
  g:drawWorldBody(2, 720, 1280)
  g:drawWorldBody(2, 720, 1280)                            -- again, same map
  Pipelines.drawWorld = realDraw
  Logger.info = realInfo

  eq(#said, 1, 'one line per map per outcome, not one per frame')
  check(said[1]:find('pipeline declined', 1, true) ~= nil,
    'and it names which path ran')
  check(said[1]:find('scale 2', 1, true) ~= nil,
    'with the scale the flat pass drew at, which is what a too-small world '
    .. 'on screen is a question about')
  check(said[1]:find('playfield 720x1280', 1, true) ~= nil,
    'and the playfield it was drawn into')
end)()


-- ------------------------------ ignoreWarp has to be cleared by a free walk
--
-- THE BUG THIS EXISTS FOR, and it sealed every building. ignoreWarp is set on
-- entering one so the player does not bounce straight back out through the
-- mat they arrived on. Game3 clears it in exactly two places: at the end of a
-- completed tryWalk step, and in gridHandleInput when the pad is released.
-- A free walk runs NEITHER -- it moves the body itself and never reaches the
-- grid pad read -- so it stayed true for the whole visit and every arrival
-- warp was refused at its first line. Pokemon Centre, Mart, Game Corner: walk
-- onto the exit mat and nothing happens, for ever.
;(function()
  local g = nbGame()
  g.map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 } }
  g.data.tilesets.byId.t.behavior = { [1] = Game3.MB_ANIMATED_DOOR }
  g.ignoreWarp = true                   -- as entering a building leaves it
  g.playerX, g.playerY = 5, 5           -- somewhere that is not the mat
  local warped = 0
  g.followWarp = function() warped = warped + 1 return true end
  local ow = g:modOverworld()

  -- the crossing that takes the player OFF the arrival tile clears it
  eq(ow:onStepComplete(), false, 'an ordinary cell does not warp')
  eq(g.ignoreWarp, false, 'and the completed crossing clears ignoreWarp')

  -- now stepping onto the mat works, which it never did before
  g.playerX, g.playerY = 5, 6
  eq(ow:onStepComplete(), true, 'arriving on the mat now takes the warp')
  eq(warped, 1, 'exactly once')
end)()

-- cleared AFTER the check and only when nothing warped, which is the order
-- tryWalk uses
;(function()
  -- two adjacent mats -- a house doorway is exactly that. Clearing FIRST
  -- would warp the player out the moment they shuffled sideways onto the
  -- second one, still under the protection they entered with.
  local g = nbGame()
  g.map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 },
                  { x = 6, y = 6, id = 1, mapGroup = 1, mapNum = 1 } }
  g.data.tilesets.byId.t.behavior = { [1] = Game3.MB_ANIMATED_DOOR }
  g.ignoreWarp = true
  g.playerX, g.playerY = 6, 6           -- shuffled onto the second mat
  local warped = 0
  g.followWarp = function() warped = warped + 1 return true end
  eq(g:modOverworld():onStepComplete(), false,
    'sliding onto the neighbouring mat under the entry protection does not '
    .. 'warp')
  eq(warped, 0, 'nothing fired')
  eq(g.ignoreWarp, false, 'but the crossing still clears it for next time')
end)()

;(function()
  -- a taken warp must NOT have its new map's protection wiped: enterMap set
  -- ignoreWarp for the map just entered, and clearing it here would send the
  -- player straight back through the door they came in
  local g = nbGame()
  g.map.warps = { { x = 5, y = 6, id = 0, mapGroup = 1, mapNum = 1 } }
  g.data.tilesets.byId.t.behavior = { [1] = Game3.MB_ANIMATED_DOOR }
  g.ignoreWarp = false
  g.playerX, g.playerY = 5, 6
  g.followWarp = function()
    g.ignoreWarp = true                 -- what enterMap does on the far side
    return true
  end
  eq(g:modOverworld():onStepComplete(), true, 'the warp is taken')
  eq(g.ignoreWarp, true,
    "and the destination's own protection survives -- otherwise the player "
    .. 'arrives and is immediately sent back')
end)()


-- ------------------------------------------ water is not walkable on foot
--
-- Collision is only half the rule in Gen 3. Water is collision 0 -- it has to
-- be, you surf across it -- and what stops you walking onto it is its
-- metatile BEHAVIOUR. Answering from the collision bits alone told a free
-- walk every lake and every stretch of sea was walkable, and it obliged: the
-- player rode a bike out across open water.
;(function()
  local g = nbGame()
  -- one water cell and one ordinary cell, both collision 0
  g.map.grid[1] = 1          -- metatile 1, collision 0
  g.map.grid[2] = 2          -- metatile 2, collision 0
  g.data.tilesets.byId.t.behavior = { [2] = Game3.MB_POND_WATER }
  local m = g:modOverworld().map
  eq(m:isWalkableCell(0, 0), true, 'ordinary ground is walkable')
  eq(Game3.collisionOf(g.map.grid[2]), 0,
    'the water cell is collision 0 -- which is exactly why collision alone '
    .. 'could not tell them apart')
  eq(m:isWalkableCell(1, 0), false, 'and water is NOT walkable on foot')

  -- surfing changes the answer, which is what the caller relies on
  g.surfing = true
  eq(g:modOverworld().map:isWalkableCell(1, 0), true,
    'a surfing player may enter the same cell')
  g.surfing = false
  eq(g:modOverworld().map:isWalkableCell(1, 0), false, 'and not otherwise')

  -- collision still blocks, as before
  g.map.grid[3] = 3 + 1024   -- collision 1
  eq(g:modOverworld().map:isWalkableCell(2, 0), false,
    'a collision-blocked cell is still blocked')
end)()

-- ------------------------- a retired pipeline is told it is off, exactly once
--
-- guard() marks a throwing pipeline broken and refuses every callback from
-- then on -- right for DRAWING, which degrades to the flat 2D path. But the
-- voxel mod also replaces the WALK, and decides whether it is driving from the
-- level the engine last handed it in `update`. A pipeline that threw stopped
-- hearing anything, including the player switching it off, so it went on
-- owning the walk over a world it was no longer drawing: the player slid
-- around the flat map, across water, unable to hand control back.
;(function()
  local Pipelines = require('src.render.Pipelines')
  local seen = {}
  local throwOnce = true
  -- registration is the content registry's job; install() reads that table
  Pipelines.install({ render_pipelines = { standdown_test = {
    label = 'TEST', levels = { 'OFF', 'ON' }, priority = 1,
    update = function(dt, level)
      seen[#seen + 1] = level
      if throwOnce then throwOnce = false error('boom') end
    end,
    drawWorld = function() return nil end,
  } } })
  Pipelines.setLevel('standdown_test', 1)

  Pipelines.update(1 / 60)
  eq(seen[1], 1, 'the first tick carries the live level')
  eq(seen[2], 0, 'and the throw is followed immediately by a stand-down at 0')

  -- and never again: the pipeline threw, and calling it forever is what the
  -- retirement exists to prevent
  Pipelines.update(1 / 60)
  Pipelines.update(1 / 60)
  eq(#seen, 2, 'no further calls after the stand-down')
  Pipelines.install(nil)
end)()


-- ------------------------- the map view names itself the way a mod expects
--
-- THE GAP THIS CLOSES, and it was the whole visual difference from Emerald.
-- The mod resolves every shape profile -- per-tileset pins, per-map overlays,
-- terrain kind -- through one lookup keyed by the map's identity. Its own
-- table is generated from pokeemerald and keyed MAP_G<g>_N<n>; Ruby's ids are
-- "g0_2", so `entry` was nil on every map, all four fields came back nil, and
-- every cell fell to the profile of last resort. Flat grass, an unsupported
-- bike path, blank interior walls -- one missing join, not fifty missing
-- shapes.
;(function()
  local MapNames = require('src.world.gen3.MapNames')
  local n = 0
  for _ in pairs(MapNames.byId) do n = n + 1 end
  eq(n, 394, "every map in pokeruby's map_groups.json is named")
  eq(MapNames.of('g0_2'), 'MauvilleCity', 'group 0 number 2 is Mauville')
  eq(MapNames.of('g0_25'), 'Route110',
    'and Route110 -- the Cycling Road, which the mod ships a per-map overlay '
    .. 'for')
  eq(MapNames.of('g0_7'), 'SootopolisCity', 'and Sootopolis, which has one too')
  eq(MapNames.of('g99_99'), nil, 'an id with no map answers nil, not a guess')
  eq(MapNames.of(nil), nil, 'and so does no id at all')
end)()

;(function()
  local g = nbGame()
  g.map.id = 'g0_2'
  local def = g:modMapView(g.map).def
  eq(def.name, 'MauvilleCity',
    "the view states the cartridge's own name for the map")
  -- an unknown id is left unnamed rather than invented: the mod then applies
  -- no per-map overlay, which is the right answer for a map it knows nothing
  -- about
  local g2 = nbGame()
  g2.map.id = 'not_a_real_map'
  eq(g2:modMapView(g2.map).def.name, nil, 'an unknown map is left unnamed')
end)()

-- and the tileset view states the pair's own symbols, which is the other
-- half of what the mod needs
;(function()
  local g = nbGame()
  g.data.tilesets.byId.t.primaryKey = 'gTileset_General'
  g.data.tilesets.byId.t.secondaryKey = 'gTileset_Mauville'
  local ts = g:modMapView(g.map).tileset
  eq(ts.primaryKey, 'gTileset_General', 'the primary is named')
  eq(ts.secondaryKey, 'gTileset_Mauville', 'and the secondary')
  check(ts.primaryKey ~= ts.id,
    'and neither is our ordinal, which names nothing a profile can key on')
end)()

-- the mod asks for ours in a way that leaves Gen 1 and Gen 2 untouched
;(function()
  local f = io.open('C:/Users/Feces/AppData/Roaming/LOVE/pokemon-love2d/mods/'
    .. 'Gen2Recomped-DramaticShapes/lib/Gen3.lua', 'r')
  if not f then
    check(true, '(the installed mod is not readable from here; skipped)')
    return
  end
  local text = f:read('*a')
  f:close()
  check(text:find('ts.primaryKey or ts.primary or ctx.primaryName', 1, true)
    ~= nil, 'the host-stated tileset name is preferred over the table')
  check(text:find('ctx.mapName = def.name', 1, true) ~= nil,
    "and the host-stated map name over the table's")
  -- every one of them falls back, so an engine that states none is unchanged
  check(text:find('or ctx.primaryName', 1, true) ~= nil,
    'each is an `or` over what the table already produced, so Emerald -- '
    .. 'which needs none of this -- keeps exactly the values it had')
end)()


-- ------------------------------- the border patch is four LE words, one string
--
-- THE LITTLEROOT RING. Both Gen 3 readers in the voxel mod -- the context's
-- metatileAt and Structures' border ring -- test for an 8-byte string and
-- unpack four u16s. Given our Lua table they fell back to borderBlock, ONE
-- metatile, and every ring cell answered 468. The crown scan only groups a
-- 2x2 whose quarters differ, so a uniform ring became a hedge of thin columns
-- around every town, where Emerald -- passing the real motif -- builds one
-- round crown per tree. Side by side, that was the visible difference.
;(function()
  local g = nbGame()
  g.map.border = { 468, 469, 476, 477 }
  local b = g:modMapView(g.map).def.border
  eq(type(b), 'string', 'the patch is published as a string')
  eq(#b, 8, 'of eight bytes: four words')
  local words = {}
  for i = 0, 3 do
    words[#words + 1] = b:byte(i * 2 + 1) + b:byte(i * 2 + 2) * 256
  end
  eq(words[1], 468, 'little-endian, first quarter')
  eq(words[2], 469, 'second')
  eq(words[3], 476, 'third')
  eq(words[4], 477, 'fourth')
  check(words[1] ~= words[2] and words[1] ~= words[3],
    'and the quarters stay DIFFERENT, which is what the crown scan needs to '
    .. 'group them into one tree rather than four hedges')

  -- a full cell word survives too; the reader masks to 1024 itself
  g.map.border = { 468 + 1024 + 4096 * 3, 469, 476, 477 }
  local b2 = g:modMapView(g.map).def.border
  eq((b2:byte(1) + b2:byte(2) * 256) % 1024, 468,
    'a word carrying collision and elevation still decodes to its metatile')

  -- anything that is not a four-entry patch is left absent, so a reader falls
  -- back to borderBlock instead of decoding garbage
  local g2 = nbGame()
  g2.map.border = { 1, 2 }
  eq(g2:modMapView(g2.map).def.border, nil, 'a short patch is not published')
  local g3 = nbGame()
  g3.map.border = nil
  eq(g3:modMapView(g3.map).def.border, nil, 'nor is a missing one')
end)()


-- ------------------------------------------ the layer-type rule, all three
--
-- The voxel mod's coverAt reads this to tell a crown or roof from a second
-- course of ground. It was inverted in our copy while Ruby's own 2D pass and
-- the mod's fallback both had it right -- so on Ruby the mod was told the
-- opposite of what it would have assumed from silence.
;(function()
  local g = nbGame()
  g.data.tilesets.byId.t.layerType = {
    [201] = Game3.LAYER_NORMAL, [202] = Game3.LAYER_COVERED,
    [203] = Game3.LAYER_SPLIT,
  }
  local fake = { getWidth = function() return 512 end,
                 getHeight = function() return 512 end }
  g.layersFor = function() return fake, fake end
  local world = g:gen3WorldFor(nil, g.map, nil)
  eq(world.topIsAbovePlayer(201), true, 'NORMAL: middle + top BG, top above')
  eq(world.topIsAbovePlayer(202), false, 'COVERED: bottom + middle BG, top below')
  eq(world.topIsAbovePlayer(203), true, 'SPLIT: bottom + top BG, top above')
  -- and it agrees with Ruby's own 2D pass, which never sends COVERED to the
  -- overlay
  eq(Game3.metatileTopPassMode(Game3.LAYER_COVERED, 'overlay', false), 'skip',
    'the 2D pass keeps COVERED out of the overlay -- the two now agree')
  -- and with the rule the mod itself falls back to when a host says nothing
  for _, lt in ipairs({ Game3.LAYER_NORMAL, Game3.LAYER_COVERED, Game3.LAYER_SPLIT }) do
    local mid = 200 + lt + 1
    eq(world.topIsAbovePlayer(mid), lt ~= 1,
      "matches the mod's own fallback `layer ~= 1` for layer type " .. lt)
  end
end)()

-- the object events reach the mod, so an occupied pocket reads as a room
;(function()
  local g = nbGame()
  g.map.objects = { { x = 7, y = 2, localId = 1, graphicsId = 58 } }
  local def = g:modMapView(g.map).def
  check(def.objects ~= nil, 'the map def carries its object events')
  eq(def.objects[1].x, 7, "with the engine's own cell coordinates")
  eq(def.objects[1].y, 2, 'both axes -- the nurse behind a Pokemon Center counter')
end)()


-- -------------------------------- the map fields the structure pass indexes
--
-- THE ROOT OF THE WHOLE VISUAL GAP, found by running both engines. Emerald's
-- and Ruby's copies of the voxel mod classified Littleroot identically, cell
-- for cell, yet Emerald built 277 structure runs and Ruby built 0. The mod's
-- Structures.forMap caches its half-built result and THEN runs its passes, and
-- the first pass reads `map.doorTiles[map:cellTile(cx, cy)]`. With no doorTiles
-- on our view that line threw, the caller's pcall swallowed it, and every
-- later pass -- building runs, roof massing, carved crowns, props -- was skipped
-- for the life of the map. Textured cubes instead of sculpted trees.
;(function()
  local g = nbGame()
  local m = g:modMapView(g.map)
  check(type(m.doorTiles) == 'table', 'the map view carries doorTiles')
  eq(m.doorTiles[Game3.MB_NON_ANIMATED_DOOR], true, 'non-animated door (0x60)')
  eq(m.doorTiles[Game3.MB_ANIMATED_DOOR], true, 'animated door (0x69)')
  eq(m.doorTiles[Game3.MB_WATER_DOOR], true, 'water door (0x6C)')
  eq(m.doorTiles[0], nil, 'plain ground is not a door')
  -- the exact expression the structure pass evaluates, which must not throw
  local ok = pcall(function() return m.doorTiles[m:cellTile(0, 0)] end)
  check(ok, "Structures' door-fold lookup evaluates without throwing")

  -- a door cell reads as a door through that same expression
  g.map.grid[1] = 7                                   -- metatile 7, collision 0
  g.data.tilesets.byId.t.behavior = { [7] = Game3.MB_ANIMATED_DOOR }
  local m2 = g:modMapView(g.map)
  eq(m2.doorTiles[m2:cellTile(0, 0)], true, 'a walkable door cell is found')

  -- blocked and off-map cells answer 0xFF, as Emerald's cellTile does
  g.map.grid[2] = 8 + 1024                            -- collision 1
  local m3 = g:modMapView(g.map)
  eq(m3:cellTile(1, 0), 0xFF, 'a collision-blocked cell answers 0xFF')
  eq(m3:cellTile(-1, 0), 0xFF, 'and so does a cell off the body')
end)()

;(function()
  local g = nbGame()
  local m = g:modMapView(g.map)
  eq(m.widthCells, g.map.width, 'widthCells is the width -- one metatile is one cell')
  eq(m.heightCells, g.map.height, 'and heightCells the height')
  -- TileShape's sealed-pocket index, which did arithmetic on a nil
  local ok = pcall(function() return 2 * m.widthCells + 3 end)
  check(ok, 'the sealed-pocket index arithmetic works')
  check(m.widthCells ~= g.map.width * 2,
    "and it is NOT WorldFillProps' Gen 1 fallback of def.width * 2")
end)()


-- ------------------------------------------ src.ui.Screens on Gen 3
--
-- THE CRASH: the voxel mod's free walk handles START with
-- `Screens.push(Game, "StartMenu")`. On Ruby that reached Gen 1's screen stack
-- and Gen 1's start menu, which read `game.party` as a Gen 1 table:
--   src/ui/StartMenu.lua:40: attempt to get length of field 'party'
-- It fired on the START that CLOSES Ruby's menu: stepField shuts the menu,
-- walkHeld runs later in the same logic step, and the free walk then saw the
-- same press with no menu up.
;(function()
  local Input = require('src.core.Input')
  local g = seamGame()
  Gen3Compat.bind(function() return g end)
  local Screens = Gen3Compat.resolve('src.ui.Screens', 'test')
  check(Screens ~= nil, 'src.ui.Screens resolves on Ruby')
  check(Screens ~= package.loaded['src.ui.Screens'] or package.loaded['src.ui.Screens'] == nil,
    "and it is not Gen 1's screen stack")

  -- no START this step: the request opens Ruby's own menu
  Input.pressed = {}
  eq(g.field, nil, 'no menu to begin with')
  Screens.push(nil, 'StartMenu')
  eq(g.field and g.field.kind, 'menu', "push('StartMenu') opens Ruby's start menu")

  -- and asking again leaves it alone rather than resetting the cursor
  g.field.cursor = 3
  Screens.push(nil, 'StartMenu')
  eq(g.field.cursor, 3, 'a second open request does not reset the menu')

  -- START pressed THIS step: the engine already opened or closed the menu,
  -- so the request must do nothing -- otherwise START can never close it
  g.field = nil
  Input.pressed = { start = true }
  Screens.push(nil, 'StartMenu')
  eq(g.field, nil, 'a same-step START press is left to the engine: the menu it '
    .. 'just closed stays closed')
  Input.pressed = {}

  -- a screen Ruby does not have is refused, not faked
  eq(Screens.push(nil, 'HordeGameOver'), nil, 'an unknown screen is refused')
  eq(g.field, nil, 'and nothing is opened in its place')
end)()

-- the engine's own START opens the menu through the same method
;(function()
  local g = seamGame()
  local calls = 0
  local real = g.openStartMenu
  g.openStartMenu = function(self) calls = calls + 1 return real(self) end
  local Input = require('src.core.Input')
  -- queued, not written to `pressed`: Input:step() rebuilds pressed from the
  -- queue at the top of every logic step, so a direct write is wiped first
  Input.pressQueue = { 'start' }
  local ok, err = pcall(function() g:logicStep(1 / 60) end)
  Input.pressQueue = {}
  Input.pressed = {}
  check(ok, 'the logic step ran: ' .. tostring(err))
  check(calls >= 1, "the field's START press goes through openStartMenu")
  eq(g.field and g.field.kind, 'menu', 'and the menu is open')
end)()

S.finish()
