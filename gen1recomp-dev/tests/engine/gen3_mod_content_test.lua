-- GEN 2 / GEN 3 CONTENT MODS ON RUBY.
--
-- Every mod content registry used to be gated on Gen 3, which did more than
-- refuse writes: Loader:load installs a registry's `base` from
-- Schemas.targetFor, and a gated registry resolves no target -- so `get`
-- folded against nothing and every read answered nil too.  A mod that only
-- READS the game (an encounter radar, a dex tool) was therefore dead on Ruby
-- for a reason that had nothing to do with it.
--
-- What is pinned here:
--
--   * Ruby's records live one level below the registry's name, and the routed
--     path is that sub-path -- routing `pokemon` at `pokemon` would fold a
--     species in beside `count` and `dexOffset`;
--   * the numeric id space actually resolves.  Ruby keys moves/items/trainers/
--     sprites/pokemon by the cart's index while a registry id is a string, and
--     without a resolver the join succeeds and every lookup answers nil --
--     a failure that looks exactly like "this game has no moves";
--   * a Ruby record passes the Gen 3 schema and a Red record does not, and the
--     reverse, so a shape is judged against the game it came from;
--   * reading is opened separately from writing: a registry with no Gen 3
--     record shape is readable and still refuses writes, because folding a
--     Red-shaped record into a Hoenn table silently is worse than a drop.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Schemas = require("src.mods.Schemas")
local Registry = require("src.mods.Registry")

local S = require("tests.harness").suite("gen3 mod content")
local check, eq = S.check, S.eq

-- ------- routing

do
  check(type(Schemas.GEN3) == "table", "Ruby has a routing table of its own")
  -- The table is SPARSE, as Gen2Recomped's registries are: a name absent from
  -- it keeps the shared target, and only an explicit `false` gates.  So a row
  -- is either a path (Ruby stores it somewhere of its own) or false (Ruby has
  -- nowhere to put it at all), and both have to resolve accordingly.
  for name, path in pairs(Schemas.GEN3) do
    check(Schemas.REGISTRIES[name] ~= nil, name .. " is a real registry")
    check(path == false or (type(path) == "string" and path ~= ""),
      name .. " is either a path or an explicit refusal")
    if path then
      eq(Schemas.targetFor(name, Schemas.REGISTRIES[name], 3), path,
        name .. " resolves the routed path")
    else
      eq(Schemas.targetFor(name, Schemas.REGISTRIES[name], 3), nil,
        name .. " resolves to no target at all")
      check(Schemas.gatedFor(name, 3), name .. " is refused")
    end
  end
end

do
  -- the sub-path, not the namespace above it
  eq(Schemas.GEN3.pokemon, "pokemon.byIndex", "species live at .byIndex")
  eq(Schemas.GEN3.encounters, "encounters.byMap", "encounters live at .byMap")
  eq(Schemas.GEN3.maps, "maps.maps", "maps live at .maps")
  -- Two registries legitimately route AT their own name, and both are
  -- registries of engine behaviour rather than cartridge records: Game3:load
  -- installs render_pipelines itself, and `screens` comes into existence as
  -- the merge because Ruby's data carries no screens key of its own.  Every
  -- registry of CART records has to route below its name, or a mod's record
  -- folds in beside the namespace's own counters and offsets.
  -- `strings` joins them for the same reason: its record is one English source
  -- string mapped to its replacement, which no cartridge's layout owns.
  local ROOT_OK = { render_pipelines = true, screens = true, strings = true }
  for name, path in pairs(Schemas.GEN3) do
    if path and not ROOT_OK[name] then
      check(path ~= name,
        name .. " routes below its own name, not at it")
    end
  end
  eq(Schemas.GEN3.render_pipelines, nil,
    "render_pipelines needs no row: the shared target is already right")
  eq(Schemas.GEN3.screens, nil, "and screens need none either")
  -- ...and the exception list is not a place to hide a cart registry
  for name in pairs(ROOT_OK) do
    check(Schemas.REGISTRIES[name].gen3Fields == nil,
      name .. " describes no cartridge record, which is why it may sit at its "
        .. "own name")
  end
end

-- ------- the numeric id space
--
-- This is the failure that looked like success: without the resolver the
-- registry HAS a base and every single get() answers nil.  So the assertion
-- is about what comes back, not about whether the lookup ran.

local function registryFor(name, base)
  local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], 3)
  local r = Registry.new(name, spec)
  r.base = function() return base end
  return r
end

do
  -- keys the cart's way: numbers, from zero
  local moves = { [0] = { id = 0, name = "NONE" },
                  [1] = { id = 1, name = "POUND" },
                  [2] = { id = 2, name = "KARATE CHOP" } }
  local r = registryFor("moves", moves)
  eq(r:get("1"), moves[1], "a decimal string id resolves the numeric key")
  eq(r:get("0"), moves[0], "including zero, which the cart uses")
  -- A Gen 1 style NAME now resolves, deliberately: Ruby keys these tables by
  -- the cart's number and every mod written elsewhere says the name, so
  -- G3.numberedById reads the record's own `name` when the key misses.  It is
  -- the reason mod.content.pokemon:get("MEW") works at all.
  eq(r:get("POUND"), moves[1], "a Gen 1 style name resolves through the record")
  eq(r:get("NONE"), moves[0], "including at the zero the cart starts from")
  check(r:get("9999") == nil, "and an id the cart has no record for is nil")
  -- the whole table, not just the one that was easy
  local resolved = 0
  for k in pairs(moves) do
    if r:get(tostring(k)) ~= nil then resolved = resolved + 1 end
  end
  eq(resolved, 3, "every id the engine has comes back")
end

do
  -- the string-keyed registries must NOT have been coerced by the same rule
  local maps = { g0_9 = { id = "g0_9", width = 20, height = 20 } }
  local r = registryFor("maps", maps)
  eq(r:get("g0_9"), maps.g0_9, "a map id is a string and resolves as one")
end

do
  -- every routed numeric registry carries a resolver, or its reads are dead
  for _, name in ipairs({ "pokemon", "moves", "items", "trainers", "sprites" }) do
    local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], 3)
    check(type(spec.baseAt) == "function",
      name .. " has a Gen 3 id resolver")
    -- and it is the resolver, not some leftover Gen 1 one
    local base = { [7] = "seven" }
    eq(spec.baseAt(base, "7"), "seven", name .. "'s resolver reads the index")
  end
end

-- ------- record shapes

local RUBY_SPECIES = {
  id = 25, name = "PIKACHU", hp = 35, atk = 55, def = 30,
  spa = 50, spd = 40, spe = 90, type1 = 13, type2 = 13,
  catchRate = 190, expYield = 82, genderRatio = 127, eggCycles = 10,
  eggGroup1 = 5, eggGroup2 = 6, ability1 = 9, ability2 = 0,
  growthRate = 0, bodyColor = 2, height = 4, weight = 60,
}
local RED_SPECIES = {
  id = "PIKACHU", name = "PIKACHU", dex = 25, types = { "ELECTRIC" },
  baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 },
  catchRate = 190, baseExp = 82, level1Moves = {}, growthRate = "MEDIUM_FAST",
  learnset = {}, evolutions = {}, spriteFront = "a.png", spriteBack = "b.png",
  frontSize = 5,
}

do
  local g3 = Schemas.shapeFor("pokemon", Schemas.REGISTRIES.pokemon, 3)
  local g1 = Schemas.REGISTRIES.pokemon
  -- the 2x2: each record passes its own game's schema and fails the other's
  check(Schemas.check(g3, "pokemon", "25", RUBY_SPECIES, "register"),
    "a Ruby species passes the Gen 3 schema")
  check(not Schemas.check(g3, "pokemon", "25", RED_SPECIES, "register"),
    "a Red species does not")
  check(Schemas.check(g1, "pokemon", "PIKACHU", RED_SPECIES, "register"),
    "a Red species passes the Gen 1 schema")
  check(not Schemas.check(g1, "pokemon", "PIKACHU", RUBY_SPECIES, "register"),
    "and a Ruby species does not")
end

do
  -- the encounter slot is the single most common porting mistake: Ruby gives
  -- a slot a level RANGE where Red gives one level
  local g3 = Schemas.shapeFor("encounters", Schemas.REGISTRIES.encounters, 3)
  check(Schemas.check(g3, "encounters", "g0_49",
    { water = { rate = 4, slots = { { species = 183, minLevel = 20,
                                      maxLevel = 30 } } } }, "register"),
    "a Ruby encounter record passes")
  check(not Schemas.check(g3, "encounters", "g0_49",
    { water = { rate = 4, slots = { { species = 183, level = 20 } } } },
    "register"),
    "a Red-shaped slot (one level, no range) is refused")
end

do
  -- and the map body: Ruby's is `grid`, Red's is `blocks`
  local g3 = Schemas.shapeFor("maps", Schemas.REGISTRIES.maps, 3)
  check(Schemas.check(g3, "maps", "g0_9",
    { id = "g0_9", width = 2, height = 1, grid = { 1, 2 } }, "register"),
    "a Ruby map record passes")
  check(not Schemas.check(g3, "maps", "g0_9",
    { id = "g0_9", width = 2, height = 1, blocks = { 1, 2 } }, "register"),
    "a Red map body (blocks, no grid) is refused")
end

-- ------- the engine's own text

do
  eq(Schemas.GEN3.strings, nil,
    "engine-authored text needs no row: the shared target is already right")
  check(not Schemas.gatedFor("strings", 3),
    "and may be written: the record is a string keyed by a string")
  -- The write has to be judged against SOMETHING, and for this registry the
  -- Gen 1 schema IS the right one -- unlike the cart registries, which carry a
  -- gen3* shape precisely because Red's fields would be the wrong yardstick.
  eq(Schemas.REGISTRIES.strings.gen3Fields, nil,
    "with no Gen 3 record shape, because there is no Gen 3 record")
  local spec = Schemas.REGISTRIES.strings
  local ok = Schemas.check(spec, "strings", "But, it failed!", "Echec !",
    "override", 3)
  check(ok, "so a translation passes the shared schema on Ruby")
  -- and the shape is still a shape: a table where a string belongs is refused
  local bad = Schemas.check(spec, "strings", "But, it failed!", {}, "override", 3)
  check(not bad, "while a non-string replacement is refused")
end

-- ------- read is not write

do
  local readOnly = Schemas.readOnlyFor(3)
  check(#readOnly > 0, "some registries are readable but not writable")
  for _, name in ipairs(readOnly) do
    check(Schemas.targetFor(name, Schemas.REGISTRIES[name], 3) ~= nil,
      name .. " resolves a target, so a mod can read it")
    check(Schemas.gatedFor(name, 3),
      name .. " still refuses writes")
    -- It may well carry a gen3* key -- the numeric ones all carry a
    -- gen3BaseAt so they can be READ -- but it describes no gen3 RECORD, and
    -- that is the thing a write would be judged against.
    local spec = Schemas.REGISTRIES[name]
    check(spec.gen3Fields == nil and spec.gen3Value == nil
      and spec.gen3Keys == nil and spec.gen3KeyValue == nil,
      name .. " is read-only precisely because it describes no Gen 3 record")
  end
end

do
  -- the writable ones are writable because they DO describe a Gen 3 record
  for _, name in ipairs({ "pokemon", "encounters", "maps" }) do
    check(not Schemas.gatedFor(name, 3), name .. " accepts writes")
    check(Schemas.REGISTRIES[name].gen3Fields ~= nil,
      name .. " describes a Gen 3 record, which is why it may be written")
  end
  -- and a registry with no Ruby home at all is refused outright, with nothing
  -- to read either -- a different answer from "readable but not writable"
  check(Schemas.gatedFor("transitions", 3), "transitions are refused")
  eq(Schemas.targetFor("transitions", Schemas.REGISTRIES.transitions, 3), nil,
    "and resolve no target, so there is nothing to read")
end

-- ------- the other generations are untouched

do
  eq(Schemas.targetFor("maps", Schemas.REGISTRIES.maps, 2), "gen2Maps",
    "Gold still routes maps to gen2Maps")
  eq(Schemas.targetFor("maps", Schemas.REGISTRIES.maps, 1),
    Schemas.REGISTRIES.maps.target, "Red still uses the catalog target")
  check(not Schemas.gatedFor("pokemon", 1), "nothing new is gated on Red")
  check(not Schemas.gatedFor("pokemon", 2), "nor on Gold")
  -- a derived spec carries no overlay keys for ANY generation, or resolving
  -- one again would hand back a different shape
  local g3 = Schemas.shapeFor("pokemon", Schemas.REGISTRIES.pokemon, 3)
  check(g3.gen3Fields == nil and g3.gen2Fields == nil,
    "a derived spec carries no overlay keys")
  eq(Schemas.shapeFor("pokemon", g3, 3), g3, "so shapeFor is idempotent")
  -- and the two generations do not share one cache slot
  local g2 = Schemas.shapeFor("encounters", Schemas.REGISTRIES.encounters, 2)
  local g3e = Schemas.shapeFor("encounters", Schemas.REGISTRIES.encounters, 3)
  check(g2 ~= g3e, "Gold and Ruby get different derived specs")
  eq(g2.target, "gen2Encounters", "Gold's keeps Gold's path")
  eq(g3e.target, "encounters.byMap", "Ruby's keeps Ruby's")
end

-- ------- the stores added after the first nine

do
  -- Ruby's audio is numbered MP2K tracks under data.audio, and Game3:playSe
  -- reads audio.songs directly -- so `music` is the route that means anything
  -- here.  There is no audio.sfx at all, which is why `sfx` stays unrouted.
  eq(Schemas.GEN3.music, "audio.songs", "music routes to the track store")
  eq(Schemas.GEN3.cries, "audio.cries", "cries route to the cry store")
  -- explicit `false`, not absent: under a sparse table absence would mean
  -- "keep the shared target", which for sfx is a table Ruby never reads
  eq(Schemas.GEN3.sfx, false,
    "sfx has no Gen 3 home: Ruby's effects are numbered tracks, not files")
  check(Schemas.gatedFor("sfx", 3), "so it is refused outright")
  -- both are numbered, so both need the resolver or every read answers nil
  for _, name in ipairs({ "music", "cries" }) do
    local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], 3)
    check(type(spec.baseAt) == "function", name .. " has the numeric resolver")
    eq(spec.baseAt({ [12] = "track" }, "12"), "track",
      name .. " reads the cart's own index")
  end
  -- read-only: no Gen 3 record describes an MP2K header + tracks structure
  check(Schemas.gatedFor("music", 3), "music is readable but not writable")
  check(Schemas.gatedFor("cries", 3), "and so are cries")
end

do
  -- A SCREEN IS A FACTORY, so nothing about the record is generation-specific
  -- and it is writable without a gen3Fields of its own -- the same reason
  -- render_pipelines is.
  eq(Schemas.GEN3.screens, nil, "screens need no row of their own")
  check(not Schemas.gatedFor("screens", 3), "and may be written")
  check(Schemas.REGISTRIES.screens.gen3Fields == nil,
    "with no Gen 3 record shape, because a factory has no cartridge shape")
  local spec = Schemas.shapeFor("screens", Schemas.REGISTRIES.screens, 3)
  check(Schemas.check(spec, "screens", "QuestLog",
    { new = function() end }, "register"), "a factory table is accepted")
  check(Schemas.check(spec, "screens", "QuestLog",
    function() end, "register"), "so is a bare function")
  check(not Schemas.check(spec, "screens", "QuestLog", 42, "register"),
    "a number is not a screen")
end

do
  -- sprites became writable, and the pose tables are the part a ported Gen 1
  -- record gets wrong: Ruby names frames per direction
  local g3 = Schemas.shapeFor("sprites", Schemas.REGISTRIES.sprites, 3)
  eq(g3.target, "sprites.byId", "sprites route to the object-strip store")
  check(not Schemas.gatedFor("sprites", 3), "and may now be written")
  check(Schemas.check(g3, "sprites", "7", {
    id = 7, path = "a.png", width = 16, height = 32, frameCount = 9,
    face = { down = 0, up = 1, left = 2, right = 2 },
    walk = { down = { 3, 4 }, up = { 5, 6 } },
  }, "register"), "a Ruby sprite record passes")
  check(not Schemas.check(g3, "sprites", "7", {
    id = 7, path = "a.png", width = 16, height = 32, frameCount = 9,
    face = { down = "frame0" },
  }, "register"), "a face table of names rather than frame indices is refused")
  check(not Schemas.check(g3, "sprites", "7",
    { id = "NPC", path = "a.png", frames = 3 }, "register"),
    "and a Gen 1 shaped record is refused")
end

-- ------- a FORCED mod's wrong-shaped record is dropped, not fatal
--
-- Opening a registry for writes has a cost that is easy to miss: a write that
-- used to be dropped with a warning is now VALIDATED, and at api level 2 a
-- validation failure fails the whole mod.  That is right for a mod that
-- claimed this game and wrong for one that was forced onto it -- its author
-- never targeted Ruby, so a Gen 1-shaped record is the expected outcome.
--
-- Wilds of Kanto is the case that proved it: one Gen 1-shaped placeholder
-- sprite took down a mod whose thirteen hundred runtime sheets were loading
-- perfectly, the moment Ruby could validate sprites at all.

do
  local Loader = require("src.mods.Loader")
  local GameVersion = require("src.core.GameVersion")
  local was = GameVersion.get()
  GameVersion.set("ruby")

  local loader = Loader.new({ fs = { read = function() end,
                                     getInfo = function() end,
                                     getDirectoryItems = function() return {} end } })
  eq(loader.generation, 3, "a Ruby loader is generation 3")

  local RED_SPRITE = { id = "SPRITE_X", image = "a.png", frames = 3 }
  local RUBY_SPRITE = { id = 7, path = "a.png", width = 16, height = 32,
                        frameCount = 9 }

  local function modNamed(id, forced)
    return { path = "mods/" .. id, forcedGen2 = forced or nil,
             -- permissionSet is normally filled by Manifest.parse; _api reads
             -- it directly, so a hand-built record has to carry it
             manifest = { id = id, api = 2, version = "1.0.0",
                          games = { "ruby" }, permissionSet = {} } }
  end

  -- claimed this game: a wrong-shaped record is the author's bug, and api 2
  -- asks for that to be fatal
  local claimed = modNamed("claimed_mod")
  local api1 = loader:_api(claimed)
  local ok = pcall(function()
    api1.content.sprites:register("SPRITE_X", RED_SPRITE)
  end)
  check(not ok, "a claiming mod's wrong-shaped record raises")

  -- forced here: the same record is dropped and the mod lives
  local forced = modNamed("forced_mod", true)
  local api2 = loader:_api(forced)
  local before = #loader.errors
  local ok2, result = pcall(function()
    return api2.content.sprites:register("SPRITE_X", RED_SPRITE)
  end)
  check(ok2, "a forced mod's wrong-shaped record does not raise")
  eq(result, nil, "the registration is dropped")
  check(#loader.errors > before, "and it is reported into the manager's feed")
  local said = loader.errors[#loader.errors]
  check(type(said) == "string", "the feed entry is a message")
  check(type(said) == "string" and said:find("forced_mod", 1, true) ~= nil,
    "naming the mod")
  check(type(said) == "string" and said:find("SPRITE_X", 1, true) ~= nil,
    "and the record")

  -- ...and a RIGHT-shaped record from a forced mod still lands
  local made = api2.content.sprites:register("7", RUBY_SPRITE)
  check(made ~= nil, "a forced mod's correctly-shaped record is accepted")

  -- the flood guard: one report per mod per registry, not one per record
  local noisy = modNamed("noisy_mod", true)
  local api3 = loader:_api(noisy)
  local base = #loader.errors
  for i = 1, 50 do
    pcall(function()
      api3.content.sprites:register("SPRITE_" .. i, RED_SPRITE)
    end)
  end
  eq(#loader.errors - base, 1,
    "fifty wrong-shaped records report once, not fifty times")

  GameVersion.set(was)
end

-- ------- the convergence gate
--
-- Gen2Recomped's forty shared registries already carry the SAME base target
-- this catalogue does (pokemon -> "pokemon", maps -> "maps", ...), so a row in
-- Schemas.GEN3 is never a Gen 3 fact -- it is a Game3.lua storage quirk, and
-- THE TARGET STATE FOR THE TABLE IS EMPTY.  There are exactly two quirks:
--
--   sub-path   Game3 keeps records one level down (pokemon.byIndex), so the
--              target has to name the table that holds them
--   numbered   Game3 keys them by the cart's number where a mod says the name
--
-- Every routed row must be one of those, and the count is pinned so it can
-- only move deliberately.  When Ruby's storage is normalised the rows come
-- out, this number goes to zero, and Ruby routes content like every other
-- version -- which is what turns a future move onto a shared Gen 3 core into
-- a deletion rather than a reconciliation.
do
  local QUIRK = {
    pokemon = "sub-path + numbered", moves = "sub-path + numbered",
    items = "sub-path + numbered", trainers = "sub-path + numbered",
    sprites = "sub-path", maps = "sub-path", tilesets = "sub-path",
    encounters = "sub-path", music = "sub-path + numbered",
    cries = "sub-path + numbered",
  }
  local routed = {}
  for name, path in pairs(Schemas.GEN3) do
    if path then routed[#routed + 1] = name end
  end
  table.sort(routed)
  for _, name in ipairs(routed) do
    check(QUIRK[name] ~= nil,
      name .. " is routed away from the shared target with no documented "
        .. "Game3 storage quirk -- add the reason or remove the row")
  end
  eq(#routed, 10,
    "ten Game3 storage quirks remain; the target state for Schemas.GEN3 is "
      .. "zero rows, and every one removed is one less thing to reconcile")
  -- and the four that already need no Gen 3 knowledge at all, which is the
  -- shape the ten above are heading toward
  for _, name in ipairs({ "text", "strings", "screens", "render_pipelines" }) do
    eq(Schemas.GEN3[name], nil, name .. " already uses the shared target")
    eq(Schemas.targetFor(name, Schemas.REGISTRIES[name], 3),
      Schemas.REGISTRIES[name].target, name .. " resolves it")
  end
end

return S.finish()
